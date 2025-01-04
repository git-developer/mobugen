module { "name": "csv" };
##
# jq module to convert a CSV document to JSON
#
# Only very basic CSV is supported. Important restrictions:
# - Input encoding is UTF-8.
# - The first line contains column definitions.
# - Values are unquoted and do not contain field or line separator
#   (no escaping involved).
# - Numbers have JSON-compatible syntax (e.g. `1.2` or `3e4`)
#
# The JSON result values are either of type 'string' or 'number'.
# 'true', 'false' and 'null' are not used.
# Strings are trimmed (no whitespace prefix or suffix).
# Empty input lines are ignored.
#
# Example
# -------
# CSV input:
#  a,b,c,...
#  a1  ,1.5,true,...
#  a2,,false,...
#  ...
#
# JSON output:
#   [
#     {"a": "a1", "b": 1.5, "c": "true"},
#     {"a": "a2", "b": "", "c": "false"},
#     ...
#   ]
#
# Origins:
# - https://github.com/jqlang/jq/wiki/Cookbook#convert-a-csv-file-with-headers-to-json
# - https://stackoverflow.com/a/32002086/9984216
##

def trim:
  sub("^\\s+"; "") | sub("\\s+$"; "")
;

def toobject($headers):
  def tonumberq: tonumber? // .;

  . as $in
  | reduce range(0; $headers | length) as $i
      ( {}; .[$headers[$i]] = ($in[$i] | tonumberq) )
;

##
# Convert a CSV string to a JSON array.
#
# Input:     A single string containing lines separated by $linesep.
#             Each line contains fields separated by $fieldsep.
#             The first line is expected to contain column names.
# $fieldsep: field separator
# $linesep:  line separator
# Output:    A JSON array containing one object per CSV line.
#             Each object contains key/value pairs.
##
def csvtojson($fieldsep; $linesep):
  split($linesep)
  | map(select(length > 0) | split($fieldsep) | map(trim))
  | .[0] as $headers
  | reduce (.[1:][]) as $row
      ( []; . + [ $row | toobject($headers) ] )
;

##
# Convert a CSV string to JSON, using
#  "\n" as line separator and
#  $fieldsep as field separator
##
def csvtojson($fieldsep): csvtojson($fieldsep; "\n");

##
# Convert a CSV string to JSON, using
#  "\n" as line separator and
#  "," as field separator
##
def csvtojson: csvtojson(",");
