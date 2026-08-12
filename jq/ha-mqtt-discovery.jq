module { "name": "ha-discovery" };
##
# jq module containing a generator for Home Assistant MQTT Discovery configurations
##

import "dimplex" as dimplex { search: "./" };
import "ha-mqtt" as ha { search: "./" };

##
# Map register definitions to a Home Assistant MQTT device discovery message.
#
# Input:     A list of register definitions
# $version:  A (target) version string, e.g. "M3.13", "M3", "M"
# $enumlist: A list of enum definitions
# Output:    A Home Assistant MQTT device discovery message
def device_discovery_message($version; $enumlist):
  .
  | ($ENV.HA_ORIGIN_NAME // "mobugen") as $origin_name
  | ($ENV.HA_ORIGIN_URL // "https://github.com/git-developer/mobugen") as $origin_url
  | ($enumlist | ha::enums($version)) as $enums
  | dimplex::registers($version)
  | [
    .[]
    | ha::domain as $domain
    | ha::config_for($domain; $enums)
    | { (.unique_id): del(.device) + { "platform": $domain } }
  ] | {
    device: { ids: $ENV.HA_DEVICE_ID },
    origin: { name: $origin_name, support_url: $origin_url },
    components: add
  }
;

def config($version; $enumlist):
  device_discovery_message($version; $enumlist)
;
