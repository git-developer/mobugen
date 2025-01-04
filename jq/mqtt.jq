module { "name": "mqtt" };
##
# jq module containing filters to process MQTT-related values
##

##
# Map a string to lowercase without special characters.
#
# Input:      A string
# $separator: A separator
# Output:     Slug
#
# Example: "1. MÄRZ - 04. ApRiL!" | slug("-") == "1-maerz-04-april"
##
def slug($separator):
  select(type == "string" and length > 0)
  | ascii_downcase
  | gsub("Ä"; "ä")  | gsub("Ö"; "ö")  | gsub("Ü"; "ü")  | gsub("ẞ"; "ß")
  | gsub("ä"; "ae") | gsub("ö"; "oe") | gsub("ü"; "ue") | gsub("ß"; "ss")
  | gsub("[^\\w]+"; $separator)
  | ltrimstr($separator) | rtrimstr($separator)
;

##
# Map a string to a slug using "-" as separator.
##
def slug:
  slug("-")
;

##
# Create a topic for a register definition.
#
# Input:  A register definition
# Environment variables:
#   MQTT_TOPIC_PREFIX:
#         A prefix for the topic.
#         Optional.
#   MQTT_TOPIC_PARTS:
#         Comma-separated list of properties that are used as topic segments.
#         Optional. Default: "category,subcategory,domain,device,part,name"
# Output: An MQTT topic for the register
##
def topic:
  . as $item
  | $ENV.MQTT_TOPIC_PARTS // "category,subcategory,domain,device,part,name"
  | (
      [ $ENV.MQTT_TOPIC_PREFIX ] + (split(",") | map($item[.] | slug))
      | map(select(. != null))
      | join("/")
    )
;

##
# Returns a MQTT topic segment signalling
# that the state of a register is read.
##
def state:
  "state"
;

##
# Returns a MQTT topic segment signalling
# that the value of a register is updated.
##
def command:
  "set"
;

##
# Returns a topic to read the state of a register.
#
# Input:  A register definition
# Output: Topic to read the state
##
def state_topic:
  [ topic, state ] | join("/")
;

##
# Returns a topic to update the value of a register.
#
# Input:  A register definition
# Output: Topic to update the value
##
def command_topic:
  [ topic, command ] | join("/")
;
