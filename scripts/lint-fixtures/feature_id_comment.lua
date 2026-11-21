-- Fixture for scripts/lint.py: the comment below must be reported as a feature id.
-- Farm window (E09 F70): this line cites ids and must fail the check.
local s = "F70 in a string is fine"
return s
