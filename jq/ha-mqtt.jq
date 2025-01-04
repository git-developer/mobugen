module { "name": "ha" };
##
# jq module containing a generator for Home Assistant configurations
##

import "dimplex" as dimplex { search: "./" };
import "mqtt" as mqtt { search: "./" };

##
# Input:    A list of enum definitions
# $version: A (target) version string, e.g. "M3.13", "M3", "M"
# Output:   A map of maps. The keys of the outer map are register types.
#            Each inner object maps an enum's name to its descriptions.
#            Only enums and values compatible to the given version are
#            considered. Duplicates are omitted.
# Example:
#  {
#    "Holding": {
#      "Betriebsmodus": [ "Sommer", "Winter" ],
#      "Auswahl Heizkreis": [ "2.Heizkreis", "3.Heizkreis" ]
#    },
#    "Coil": {
#      "Statusmeldungen": [ 
#        "Kein Status", "Aus", "Heizen", "Schwimmbad", "Warmwasser", "Kühlen",
#        "Abtauen", "Durchflussüberwachung",
#        "Verzögerung Betriebsmodusumschaltung", "Sperre"
#      ]
#    }
#  }
# 
##
def enums($version):
  . // []
  | dimplex::enums($version)
  | group_by([.register_type, .name])
  | reduce .[] as $item ({}; . * { ($item[0] | .register_type): {
      ($item[0] | (.name)): ($item | [ .[] | .description ] | unique)
    }
  })
;

##
# Returns the `domain` (in Home Assistant terms).
#
# Input:  A register definition
# Output: The domain for the register
##
def domain:
  .
  | (.type | ascii_downcase) as $type
  | (.access | ascii_downcase) as $access
  |
  if $type == "coil" then
    if   $access == "r"  then "binary_sensor"
    elif $access == "w"  then "button"
    elif $access == "rw" then "switch"
    else null
    end
  elif $type == "holding" then
    if $access == "r"     then "sensor"
    elif .class == "text" then "text"
    elif $access == "w"   then "notify"
    elif $access == "rw"  then
      if .scale == "" and .offset == "" and .conversion != ""
      then "select"
      else "number"
      end
    else null end
  elif dimplex::isenum then "select"
  else null end
;

##
# Filters a value and wraps the result in an object.
#
# Input:  A value
# filter: A filter that is applied to the input value
# $name:  Name of the property containing the filter result 
# Output: An object containing the single property $name
#          holding the filter result as value;
#          `null` if the filter outputs nothing or an error
##
def wrap(filter; $name):
  ({ ($name): (try filter | select(. != null)) }) // null
;

##
# Returns constraints for the values of a register
#
# Input:  A register definition
# Output: An object containing the properties `min`, `max` and `step`
#          for the register, or `null` if no such constraints exist
##
def constraints:
  (.min | wrap(tonumber; "min"))
  + (.max | wrap(tonumber; "max"))
  + (.scale | wrap(tonumber; "step"))
;

##
# Returns a `device` configuration object.
#
# Environment variables:
#   HA_DEVICE_ID:
#         Device id
# Output: An object containing a `device` property,
#          or `null` if the env variable is not set
##
def device:
  $ENV.HA_DEVICE_ID as $deviceid
  | if $deviceid | type == "string"
    then { device: { identifiers: [ $deviceid ] } }
    else null end
;

##
# Returns an `options` configuration object for an enum register.
#
# Input:  A register definition
# $enums: An object with enum definitions
# Output: An object containing an `options` property with enum descriptions
##
def options($enums):
  wrap(dimplex::enum($enums); "options")
;

##
# Returns a `device_class` configuration object.
#
# Input:   A register definition
# $domain: Domain of the item (e.g. `sensor`)
# $enums:  An object with enum definitions
# Output:  An object containing the `device_class` property for the register;
#            if the register is an enum, the returned object also contains an
#            `options` property with enum descriptions
##
def device_class($domain; $enums):
  . as $item
  |
  if $domain == "binary_sensor" then
    if   .class == "lock"      then "lock"
    elif .class == "operation" then "running"
    elif .class == "open"      then "opening"
    elif .class == "problem"   then "problem"
    elif .class == "option"    then null
    else null end
  elif ($domain | IN("sensor", "number")) then
      if .unit | IN("°C", "K") then "temperature"
    elif .unit == "%"          then "humidity"
    elif .unit == "1/min"      then "frequency"
    elif .unit == "kWh"        then "energy"
    elif .unit == "W"          then "power"
    elif .class == "duration"  then "duration"
    elif dimplex::isenum
         and (.scale == "")
         and (.offset == "")   then "enum"
    else null end
  else null end
  | wrap(.; "device_class")
  + (if . == "enum" then $item | options($enums) else null end)
;

##
# Returns a `entity_category` configuration object.
#
# Input:  A register definition
# Output: An object containing a `entity_category` property for the register
##
def entity_category:
  if .access | ascii_downcase == "r"
  then "diagnostic"
  else "config"
  end
  | wrap(.; "entity_category")
;

##
# Returns a `unit_of_measurement` configuration object.
#
# Input:  A register definition
# Output: An object containing a `unit_of_measurement` property for the register
##
def unit_of_measurement:
  if dimplex::isenum then null else
    .unit | if IN(null, "") then null else
      {
        unit_of_measurement: (
          if   . == "hour" then "h"
          elif . == "1/min" then "Hz"
          else . end)
      }
    end
  end
;

##
# Returns a `state_class` configuration object.
#
# Input:  A register definition
# Output: An object containing a `state_class` property for the register
##
def state_class:
  if dimplex::isenum | not then
    {
      state_class: (
        if .category | IN("Laufzeiten", "Wärmemengen")
        then "total_increasing" else "measurement" end
      )
    }
  else null end
;

##
# Returns a configuration object for a binary register.
#
# Input:   A register definition
# $prefix: A prefix for the property names in the configuration object
# Output:  An object containing an `on` and an `off` property,
#           with values matching the `class` of the item
##
def binary($prefix):
  def flip: map_values((. + 1) % 2);
  .class as $class
  | { off: 0, on: 1 }
  | with_entries(.key = ($prefix + "_" + .key))
  | if $class == "lock" then flip else . end
;

##
# Returns a configuration object for the payload of a binary register.
#
# Input:   A register definition
# Output:  An object containing a `payload_on` and a `payload_off` property,
#           with values matching the `class` of the item
##
def payload_binary:
  binary("payload")
;

##
# Returns a configuration object for the state of a binary register.
#
# Input:   A register definition
# Output:  An object containing a `state_on` and a `state_off` property,
#           with values matching the `class` of the item
##
def state_binary:
  binary("state")
;

##
# Returns a `payload_press` configuration object.
#
# Input:   A register definition
# Output:  An object containing a `payload_press` property with value 1.
##
def payload_press:
  { payload_press: 1 }
;

##
# Returns a configuration object with basic properties for a register.
#
# Input:   A register definition
# $domain: Domain of the item (e.g. `sensor`)
# $enums:  An object with enum definitions
# Output: A configuration object with basic properties
##
def basic($domain; $enums):
  {
    name: .name,
    object_id: mqtt::topic | mqtt::slug("_"),
    unique_id: mqtt::topic | mqtt::slug("_"),
  }
  + entity_category
  + device_class($domain; $enums)
  + device
  + {
      json_attributes_template: ({}
        + wrap(.domain | select(. != ""); "domain")
        + wrap(.device | select(. != ""); "device")
        + wrap(.part   | select(. != ""); "part")
      ) | tostring
    }
  + { json_attributes_topic: mqtt::topic }
;

##
# Returns a configuration object for a writable register.
#
# Input:  A register definition
# Output: A configuration object with a `command_topic` property
#          if the register is writable; `null` otherwise
##
def command_variables:
  if .access | ascii_downcase | contains("w") | not then null
  else wrap(mqtt::command_topic; "command_topic") end
;

##
# Returns a configuration object for a readable register.
#
# Input:  A register definition
# Output: A configuration object with state/value properties
#          if the register is readable; `null` otherwise
##
def state_variables:
  (if .unit == "1/min" then "/ 60 " else "" end) as $operation
  | wrap(mqtt::state_topic; "state_topic")
  + wrap("{{ value_json.state \($operation)}}"; "value_template")
;

##
# Returns a complete configuration object for a register.
#
# Input:   A register definition
# $domain: Domain of the item (e.g. `sensor`)
# $enums:  An object with enum definitions
# Output: A configuration object containing all properties
#          for the Home Assistant config
##
def config_for($domain; $enums):
  .
  | state_variables as $state
  | command_variables as $command
  | basic($domain; enums)
  + if $domain == "binary_sensor" then $state + payload_binary
  elif $domain == "sensor"        then $state + state_class + unit_of_measurement
  elif $domain == "button"        then $command + payload_press
  elif $domain == "notify"        then $command
  elif $domain == "select"        then $command + $state + options($enums)
  elif $domain == "switch"        then $command + $state + state_binary + payload_binary
  elif $domain == "text"          then $command + $state + { max: 1, min: 1, pattern: "[A-Z]" }
  elif $domain == "number"        then $command + $state + unit_of_measurement + constraints
  else null end
;

##
# Returns a Home Assistant customization for a register,
# containing a `friendly_name` and custom attributes.
#
# Input:  A register definition
# $key:   Key for the customization property (`domain.object_id`)
# Environment variables:
#   HA_CUSTOM_ATTRIBUTES:
#         A comma-separated list of property names for custom attributes.
#         Optional. Default: "category,subcategory,domain,device,part"
# Output: An object containing the single property `$key`;
#           its value is an object containing key/value pairs for
#           `friendly_name` and custom attributes
##
def customize_for($key):
  def take($source; $target): wrap(.[($source)] | select(. != ""); $target);
  def takeall($names): . as $item | $names | [ .[] | . as $name | $item | take($name; $name) ] | add;
  ($ENV.HA_CUSTOM_ATTRIBUTES // "category,subcategory,domain,device,part")
    as $custom_attributes
  | wrap(
      take("name"; "friendly_name") + takeall($custom_attributes | split(","));
      $key)
;

##
# Map register definitions to Home Assistant MQTT configuration entries.
#
# Input:     A list of register definitions
# $version:  A (target) version string, e.g. "M3.13", "M3", "M"
# $enumlist: A list of enum definitions
# Output:    An object containing a Home Assistant configuration
def mqttconfig($version; $enumlist):
  .
  | ($enumlist | enums($version)) as $enums
  | dimplex::registers($version)
  | [
    .[]
    | domain as $domain
    | config_for($domain; $enums) as $mqtt_config
    | customize_for($domain + "." + $mqtt_config.object_id) as $customize
    | { mqtt: {($domain): $mqtt_config}, customize: $customize }
  ] | { mqtt: map(.mqtt), homeassistant: { customize: (map(.customize) | add) }
  }
;

def config($version; $enumlist):
  mqttconfig($version; $enumlist)
;
