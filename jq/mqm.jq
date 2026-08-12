module { "name": "mqm" };
##
# jq module containing a generator for mqmgateway configurations
##

import "core" as core { search: "./" };
import "dimplex" as dimplex { search: "./" };
import "mqtt" as mqtt { search: "./" };

##
# Calculate the effective Modbus address of a register.
#
# Input:  A register definition
# Environment variables:
#   MQM_ADDRESS_OFFSET:
#         Address offset (integer)
# Output: Effective Modbus address of the register
##
def address:
 .address + ($ENV.MQM_ADDRESS_OFFSET // 0 | tonumber)
;

##
# Map input enum definitions to mqmgateway map converter definitions.
#
# Input:    A list of enum definitions
# $version: A version string, e.g. "M3.13", "M3", "M"
# Output:   An object containing a `.register_type` map.
#             Each entry contains a mapping from register name
#             to enum values in mqmgateway map converter syntax
#
# Example:
#  { 
#    "Holding": { 
#      "Betriebsmodus": "0:\"Sommer\",1:\"Winter\"",
#      "Auswahl Heizkreis": "2:\"2.Heizkreis\",3:\"3.Heizkreis\""
#    },
#    "Coil": {
#      "Zustand Stellventil": "0:\"geschlossen\",1:\"geöffnet\""
#    }
#  }
##
def enums($version):
  . // []
  | dimplex::enums($version)
  | group_by([.register_type, .name])
  | reduce .[] as $item ({}; . * { ($item[0] | .register_type): {
      ($item[0] | (.name)):
      ($item | map("\(.value):\(dimplex::enumvalue | tojson)") | join(","))
    }
  })
;

##
# Build an exprtk expression to scale a value.
#
# Input:      A value
# $operator:  Scale operator
# $operand:   Operand
# Output:     An exprtk expression to scale the input if the operand holds a value;
#             unscaled input otherwise
#
# Examples:
#  "R0" | exprscale("*", 0.01) == "R0 * 0.01"
#  "M0" | exprscale("*", "")   == "M0"
##
def exprscale($operator; $operand):
  if $operand | IN("", null) | not then [., $operator, $operand] | join(" ") end
;

##
# Map a register definition to an exprtk converter.
#
# Input:      A register definition
# $direction: One of: [ "from-modbus", "to-modbus" ]
# Output:     An object containing a exprtk converter,
#              or no output (empty) if data type is unsupported
#
# Format of data type: <base type>[modifier]*
# Supported base types: [ uint16, uint32, int16, int32, flt32 ]
# Supported modifiers (may be combined in order):
#   1. bs: byte swap
#   2. l:  low register first
#
# Examples:
#   Input:      { ..., "data_type": "int32bsl", "scale": 0.1 }
#   $direction: "from-modbus",
#   => Output:  { "converter": "expr.evaluate(expression=\"uint32(R1, R0) * 0.1\", precision=1, low_first=true)" }
#
#   Input:      { ..., "data_type": "uint16" }
#   $direction: "to-modbus",
#   => Output:  { "converter": "expr.evaluate(expression=\"M0\")" }
##
def exprconverter($direction):
  .scale as $scale
  | .data_type
  | capture("^(?<type>(u?int|flt)(?<bits>16|32)(bs)?)(?<low>l)?$")
  | core::wrap(.low | length > 0 // null; "low_first")
  + {
      "from-modbus": {
        expression: if .type == "uint16" then "R0"
                    else .type + ({"32": "R0, R1"}[.bits] // "R0" | "(\(.))")
                    end | exprscale("*"; $scale),
        precision: $scale | tostring | split(".") | .[1] | length
      },
      "to-modbus": {
        expression: "M0" | exprscale("/"; $scale),
        write_as: .type
      }
    }[$direction]
  | to_entries
  | map([.key, (.value | tojson)] | join("="))
  | join(", ")
  | "expr.evaluate(\(.))"
;

##
# Map a register definition to an mqmgateway converter.
#
# Input:      A register definition
# $direction: One of: [ "from-modbus", "to-modbus" ]
# $enums:     An object containing mqmgateway map converter definitions
# Output:     An object containing a mqmgateway converter,
#              or no output (empty) if the register does not require a converter
#
# Examples:
#   Input:      { ..., "data_type": "uint16", "scale": 0.1 }
#   $direction: "from-modbus",
#   => Output:  { "converter": "expr.evaluate(expression="R0 * 0.1", precision=1)" }
#
#   Input:      { ..., "name": "Betriebsmodus", "conversion": "enum" }
#   $enums:    { "Holding": { "Betriebsmodus": "0:\"Sommer\",1:\"Winter\"" } },
#   => Output:  { "converter": "std.map('0:\"Sommer\",1:\"Winter\"')" }
##
def mqmconverter($direction; $enums):
  dimplex::enum($enums) as $enum
  | if $enum then $enum | "std.map(\(@sh))"
    elif .conversion | startswith("string") then "std.string()"
    else exprconverter($direction) end
;

##
# Map a register definition to a register count.
#
# Input:      A register definition
# Output:     An object containing the register count,
#              or no output (empty) if the register count is 1
#
# Examples:
#   Input:      { ..., "data_type": "uint32" }
#   => Output:  { "count": 2 }
#
#   Input:      { ..., "conversion": "string:5" }
#   => Output:  { "count": 3 }
##
def mqmcount:
  (.conversion | (capture("^string:(?<length>[0-9]+)$") | .length | tonumber) // null) as $chars
  | if $chars then $chars / 2
    elif .data_type | contains("32") then 2
    else empty end
;

##
# Map register definitions to mqmgateway object definitions.
#
# Input:     A list of register definitions
# $version:  A (target) version string, e.g. "M3.13", "M3", "M"
# $enumlist: A list of enum definitions
# Environment variables:
#   MQM_NETWORK:
#            mqmgateway name of the Modbus network the registers belong to
#            Optional. Default: "network"
#   MQM_SLAVE_ADDRESS:
#            Modbus slave address the registers belong to
#            Optional. Default: 1
# Output:    An object containing mqmgateway object definitions
#
# Example:
#  {
#    "mqtt": {
#      "objects": [
#        {
#          "topic": "mqmgateway/einstellungen-1-heiz-kuehlkreis/heating/hk1/raumtemperatur",
#          "network": "network",
#          "slave": 1,
#          "state": {
#              "register": 47
#              "name": "state"
#              "converter": "expr.evaluate(expression=\"R0 * 0.1\", precision=1)"
#          },
#          "commands": [{
#              "register": 47
#              "register_type": "holding"
#              "name": "set"
#              "converter": "std.divide(0.1)"
#              "converter": "expr.evaluate(expression=\"M0 / 0.1\", write_as=\"uint16\")"
#          }]
#        },
#        {
#          "topic": "mqmgateway/systemstatus/statusmeldungen",
#          "network": "network",
#          "slave": 1,
#          "state": {
#            "register": 104
#            "name": "state"
#            "converter": "std.map('0:\"Kein Status\",1:\"Aus\",2:\"Heizen\",3:\"Schwimmbad\",4:\"Warmwasser\",5:\"Kühlen\",10:\"Abtauen\",11:\"Durchflussüberwachung\",24:\"Verzögerung Betriebsmodusumschaltung\",30:\"Sperre\"')"
#        }
#      ]
#    }
#  }
#
##
def mqttobjects($version; $enumlist):
  .
  | ($ENV.MQM_NETWORK // "network")
    as $network
  | ($ENV.MQM_SLAVE_ADDRESS // 1)
    as $slave_address
  | ($ENV.MQM_RETAIN)
    as $retain
  | ($enumlist | enums($version))
    as $enums
  | dimplex::registers($version)
  | [
    .[]
    | (.access | ascii_downcase)
      as $access
    | (address | tonumber)
      as $register
    | (.type | ascii_downcase)
      as $register_type
    | ({ register: $register, name: mqtt::state }
      + if $register_type == "holding" then null
        else { register_type: $register_type } end
      + core::wrap(mqmconverter("from-modbus"; $enums); "converter")
      + core::wrap(mqmcount; "count")
      ) as $state
    | ({ register: $register, register_type: $register_type, name: mqtt::command }
      + core::wrap(mqmconverter("to-modbus"; $enums); "converter")
      + core::wrap(mqmcount; "count")
      + core::wrap(.write_mode | select(length > 0); "write_mode")
      ) as $command

    | { topic: mqtt::topic }
    + if $access | contains("r") then { state: $state } else {} end
    + if $access | contains("w") then { commands: [ $command ] } else {} end
    + { network: $network, slave: $slave_address }
    + if $retain != null then { retain: $retain | test("true") } else {} end
    + core::wrap(.refresh | select(length > 0); "refresh")
  ] | { mqtt: { objects: . } }
;

def config($version; $enumlist):
  mqttobjects($version; $enumlist)
;
