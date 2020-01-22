import os
import times
import tables
import terminal
import parseopt
import strformat
import strutils
import osproc

# Get rid of ugly shutdown text when using CTRL-C.
setControlCHook(proc () {.noconv.} = quit(0))

const version = "1.0.0"

let help = """
Usage: pych [FLAGS] SCRIPT

A tool that watches Python files and re-runs them on change.

Example: pych -c --interpreter=python myscript.py

Flags:
  -c, --clear         clear the screen on start and after reloads
  -i, --interpreter   path to a Python interpreter (default: python3)
  -v, --version       display version
  -h, --help          display this help
""".strip(chars = {'\n'})

type
  Options = object
    ## Represents all possible command-line options.
    clear: bool
    interpreter: string
    scriptPath: string

proc handleParserError(message: string) =
  writeLine(stderr, message)
  writeLine(stderr, "")
  writeLine(stderr, help)
  quit(1)

proc parseOptions(): Options =
  ## Parses the command's ARGV list. Messy, but necessary with the default
  ## library's package.
  var argumentCounter: int
  var parser = initOptParser(shortNoVal = {'c', 'v', 'h'},
    longNoVal = @["clear", "version", "help"])

  # Set default options
  result.interpreter = "python3"

  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if parser.val == "": # boolean options
        case parser.key
        of "v", "version":
          echo fmt"pych version {version}"
          quit(0)
        of  "h", "help":
          echo help
          quit(0)
        of "c", "clear":
          result.clear = true
        else:
          handleParserError(fmt"Error: unknown option {parser.key}.")
      else: # non-boolean options
        case parser.key
        of "i", "interpreter":
          result.interpreter = parser.val
        else:
          handleParserError(fmt"Error: unknown option {parser.key}.")
    of cmdArgument:
      inc(argumentCounter)
      result.scriptPath = parser.key

  if argumentCounter < 1:
    handleParserError("Error: a Python script path must be provided.")
  elif argumentCounter > 1:
    handleParserError("Error: only one script path can be provided.")

proc checkInterpreter(path: string): string =
  ## Checks if the path to the Python interpreter is valid. It does not check
  ## if the path is an actual Python executable, however. An error will be
  ## returned if something goes wrong.
  result = findExe(path)
  if result == "":
    writeLine(stderr, fmt"Error: could not find {path}.")
    quit(1)


proc checkPath(path: string): string =
  ## Checks a given path. If the path does not exist, an error will be
  ## displayed and the program will quit with an error code of 1. If the path
  ## is valid, a sanatized version of it will be returned.
  result = path
  if not fileExists(path):
    writeLine(stderr, fmt"Error: {path} does not exist.")
    quit(1)
  if not isAbsolute(path):
    result = path.absolutePath()

proc startInterpreter(inter, script: string): Process =
  result = startProcess(inter, args=[script],
    options = {poUsePath, poParentStreams})

proc collectPythonFiles(root: string): seq[string] =
  # Get top-level scripts.
  var path = joinPath(root, "*.py")
  for file in walkFiles(path): result.add(file)

  # Get lower-level scripts recursively.
  path = joinPath(root,  "**", "*.py")
  for file in walkFiles(path): result.add(file)

proc updateFiles(root: string, files: OrderedTableRef[string, Time]): bool =
  ## Update the running list of files. Returns true if there's been a
  ## modification.
  let collectedFiles = collectPythonFiles(root)
  for file in collectedFiles:
    var modTime: Time
    try:
      modTime = getLastModificationTime(file)
    except:
      discard # if something goes wrong, ignore it

    if not files.hasKey(file):
      files[file] = modTime
    elif files[file] != modTime:
      files[file] = modTime
      return true

proc writeForeground(color: ForegroundColor, content: string) =
  let ansi = ansiForegroundColorCode(color, true)
  echo ansi, content, ansiResetCode

proc clearScreen() =
  when defined(windows):
    discard execCmd("cls")
  else:
    discard execCmd("clear")

proc run(opts: Options) =
  if opts.clear: clearScreen()

  # Collect Python files recurively in this directory.
  var files = newOrderedTable[string, Time]()
  discard updateFiles(opts.scriptPath.parentDir(), files)

  var p = startInterpreter(opts.interpreter, opts.scriptPath)

  while true:
    # If a file has been modified, reload everything and alert the user.
    if updateFiles(opts.scriptPath.parentDir(), files):
      p.kill()

      if opts.clear: clearScreen()
      writeForeground(fgYellow, "~~~ File change detected. Restarted. ~~~")
      p = startInterpreter(opts.interpreter, opts.scriptPath)

when isMainModule:
  var options = parseOptions()
  options.interpreter = checkInterpreter(options.interpreter)
  options.scriptPath = checkPath(options.scriptPath)
  run(options)
