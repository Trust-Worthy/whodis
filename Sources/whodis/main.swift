import Foundation

#if os(macOS)
exit(App(arguments: Array(CommandLine.arguments.dropFirst())).run())
#else
FileHandle.standardError.write(Data("whodis only runs on macOS.\n".utf8))
exit(1)
#endif
