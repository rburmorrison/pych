# Package

version       = "1.0.0" # update version in main file too!
author        = "Ryan Burmeister-Morrison"
description   = "A tool that watches Python files and re-runs them on change."
license       = "MIT"
srcDir        = "src"
bin           = @["pych"]

# Dependencies

requires "nim >= 1.0.4"
