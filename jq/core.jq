module { "name": "core" };
##
# jq module containing core functions
##

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
