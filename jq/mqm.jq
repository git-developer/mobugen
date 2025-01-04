module { "name": "mqm" };
##
# jq module containing a generator for mqmgateway configurations
##

import "dimplex" as dimplex { search: "./" };
import "mqtt" as mqtt { search: "./" };

##
# Calculates the effective Modbus address of a register.
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
# Map input enum definitions to mqmgateway map converter definitions
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
# Map a register definition to an mqmgateway converter
#
# Input:      A register definition
# $direction: One of: [ "from-modbus", "to-modbus" ]
# $enums:     An object containing mqmgateway map converter definitions
# Output:     An object containing a mqmgateway converter,
#              or `null` if the register does not require a converter
#
# Examples:
#   Input:      { ..., "conversion": 0.1 }
#   $direction: "from-modbus",
#   => Output:  { "converter": "std.multiply(0.1)" }
#
#   Input:      { ..., "name": "Betriebsmodus", "conversion": "enum" }
#   $enums:    { "Holding": { "Betriebsmodus": "0:\"Sommer\",1:\"Winter\"" } },
#   => Output:  { "converter": "std.map('0:\"Sommer\",1:\"Winter\"')" }
##
def mqmconverter($direction; $enums):
  .name as $name
  | dimplex::enum($enums) as $enum
  | (if $enum != null then $enum | "std.map(\(@sh))"
    elif .scale | type == "number" then
      (if .data_type == "int16" then "int16(R0)" else "R0" end) as $factor
      | {
        "from-modbus": "expr.evaluate(\"\($factor) * \(.scale)\", 1)",
        "to-modbus": "std.divide(\(.scale))"
      }[$direction]
      | select(. != null)
    elif .data_type == "int16" then "std.int16()"
    else empty
    end | { "converter": . }) // null
;

##
# Map register definitions to mqmgateway object definitions
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
#    "objects": [
#      {
#        "topic": "mqmgateway/einstellungen-1-heiz-kuehlkreis/heating/hk1/raumtemperatur",
#        "state": {
#            "register": "network.1.47"
#            "name": "state"
#            "converter": "expr.evaluate(\"R0 * 0.1\", 1)"
#        },
#        "command": {
#            "register": "network.1.47"
#            "register_type": "holding"
#            "name": "set"
#            "converter": "std.divide(0.1)"
#        }
#      },
#      {
#        "topic": "mqmgateway/systemstatus/statusmeldungen",
#        "state": {
#          "register": "net.1.104"
#          "name": "state"
#          "converter": "std.map('0:\"Kein Status\",1:\"Aus\",2:\"Heizen\",3:\"Schwimmbad\",4:\"Warmwasser\",5:\"Kühlen\",10:\"Abtauen\",11:\"Durchflussüberwachung\",24:\"Verzögerung Betriebsmodusumschaltung\",30:\"Sperre\"')"
#      }
#    ]
#  }
#
##
def mqttobjects($version; $enumlist):
  .
  | ($ENV.MQM_NETWORK // "network")
    as $network
  | ($ENV.MQM_SLAVE_ADDRESS // 1)
    as $slave_address
  | ($enumlist | enums($version))
    as $enums
  | dimplex::registers($version)
  | [
    .[]
    | (.access | ascii_downcase)
      as $access
    | ([ $network, $slave_address, address ] | join("."))
      as $register
    | (.type | ascii_downcase)
      as $register_type
    | ({ register: $register, name: mqtt::state }
      + if $register_type == "holding" then null
        else { register_type: $register_type } end
      + mqmconverter("from-modbus"; $enums))
      as $state
    | ({ register: $register, register_type: $register_type, name: mqtt::command }
      + mqmconverter("to-modbus"; $enums))
      as $command

    | { topic: mqtt::topic }
    + if $access | contains("r") then { state: $state } else {} end
    + if $access | contains("w") then { command: $command } else {} end
  ] | { mqtt: { objects: . } }
;

def config($version; $enumlist):
  mqttobjects($version; $enumlist)
;
