module { "name": "dimplex" };
##
# jq module containing filters to process Dimplex-specific Modbus values
#
# == Version
#
# Dimplex uses a version number of the format
#
#   <Version><Number>.<Index>
#
# <Version> is an uppercase letter, <Number> & <Index> are positive integers.
# The numbers are optional. Examples: `M3.13`, `L23`, `H`
#
# A Dimplex system provides this version as 3 separate Modbus values.
# A register or enum definition may contain a property ".since" holding such a
# version in string format, meaning that the register or enum is available
# in a system having at least this version.
#
#
# == Enums
#
# In a Dimplex system, a Modbus register may be restricted to hold a certain
# subset of values. In this case, the register definition contains a property
# ".conversion" holding either the name of an enum or the string "enum" meaning
# that the register name is used.
# A list of enum definitions is managed in a separate document, besides the list
# of register definitions. An enum definition contains a name and a list of values.
##

##
# Convert a version string into a comparable version array.
#
# Input:  Version string
# Output: Version array
#
# Examples:
#   "M3.12" -> [ "M", 3, 12 ]
#   "M3"    -> [ "M", 3,  0 ]
#   "M"     -> [ "M", 0,  0 ]
#   ""      -> null
##
def version_array:
  (
    match("([A-Z])(?:([0-9]+)(?:\\.([0-9]+))?)?")
    | .captures
    | map(. = .string // 0)
    | map(. as $v | tonumber? // $v)
  ) // null
;

##
# Select elements compatible with a target version
#
# Input:    Elements with ".since" property containing a version string
# $version: A (target) version string, e.g. "M3.13", "M3", "M"
# id:       Filter to identify an element
# Output:   Elements that are compatible to $version
##
def matches($version; id):
  map(select((.since | version_array) <= ($version | version_array)))
  | [
    group_by(id) | .[]
    | group_by(.since)
    | max_by(.[0].since) | .[]
    ]
;

##
# Select enum values matching a target version
#
# Input:    A list of enum value definitions
# $version: A version string, e.g. "M3.13", "M3", "M"
# Output:   All enum value definitions that match the version
##
def enums($version):
  matches($version; [.register_type, .name])
;

##
# Find an enum type for a register definition
#
# Input:  A register definition
# $enums: An object with enum definitions
# Output: The enum definition matching the input register definition,
#          or null if the register has no enum type
##
def enum($enums):
  .name as $name
  | .type as $register_type
  | .conversion
  | (
      select(type == "string" and startswith("enum"))
      | ((ltrimstr("enum") | ltrimstr(":") | select(length > 0)) // $name) as $enum
      | $enums[$register_type][$enum]
  ) // null
;

##
# Select register definitions whose type is an enum
#
# Input:  Register definitions
# Output: All register definitions whose type is an enum
##
def isenum:
  .conversion | (type == "string" and length > 0)
;

##
# Get an enum value as string.
#
# Input:  An object containing a enum value definition
# Output: A string representing the enum value
##
def enumvalue:
  [.description, .part]
  | map(select(. != null and . != ""))
  | join(" ")
;

##
# Select registers matching a target version
#
# Input:    A list of register definitions
# $version: A version string, e.g. "M3.13", "M3", "M"
# Output:   All register definitions that match the version
##
def registers($version):
  matches($version; [.type, .name, .domain, .device, .part])
;
