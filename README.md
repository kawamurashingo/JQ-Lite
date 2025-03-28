# JQ::Lite

A lightweight jq-like JSON query engine in pure Perl.

## Example

```bash
cat data.json | perl script/jq.pl '.domain[] | .name'
