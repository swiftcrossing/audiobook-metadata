import ArgumentParser
import Foundation
import RegexBuilder
import ScriptingHelpers

enum AMError: Error {
  case osVersion
  case noPrefix
  case noFiles
}

struct AudiobookMetadata: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Update metadata of Humble Bundle audiobook audio files to make them conform to the audiobook standard.",
    subcommands: []
  )

  @Option(name: .shortAndLong, parsing: .next, help: "Input directory of containing audio files for audiobook.")
  private var inputDir: String

  @Option(name: .shortAndLong, parsing: .next, help: "Output directory to save updated audio files to. (default: <inputDir>)")
  private var outputDir: String?

  @Option(name: .shortAndLong, parsing: .next, help: "Audio file format to search for.")
  private var `extension`: String = "mp3"

  @Option(name: .shortAndLong, parsing: .next, help: "The portion of the filename after the chapter number. (e.g. _WinterWorldRID)")
  private var suffix: String

  @Option(name: .shortAndLong, parsing: .next, help: "Audiobook title.")
  private var title: String

  @Option(name: .shortAndLong, parsing: .next, help: "Audiobook author.")
  private var author: String

  @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes")
  private var verbose: Bool = false

  init() {}

  func run() throws {
    let audiofileCount: Int
    let filePrefixLength: Int
    let coverArtPath: String
    if #available(macOS 13.0, *) {
      let fileLines = shell("ls \(inputDir)").asString
        .split(separator: "\n")

      guard !fileLines.isEmpty else {
        throw AMError.noFiles
      }

      // Count audiofiles with expected filename format
      let filenameRegex = try Regex("\\d+_.*.\(`extension`)")
      audiofileCount = fileLines
        .filter { $0.wholeMatch(of: filenameRegex) != nil }
        .count
      print("Audiofile count: \(audiofileCount)", verbose: verbose)

      // Get length of file number (typically 2 or 3 digits)
      let filePrefixRef = Reference(Substring.self)
      let filePrefixRegex = Regex {
        Capture(as: filePrefixRef) {
          OneOrMore(.digit)
        }
        "_"
        Capture {
          OneOrMore(.word)
        }
      }
      if let filePrefixMatch = fileLines[0].firstMatch(of: filePrefixRegex) {
        filePrefixLength = filePrefixMatch[filePrefixRef].count
      } else {
        throw AMError.noPrefix
      }
      print("File number length: \(filePrefixLength)", verbose: verbose)

      // Get cover art path from inputDir
      let coverArtRegex = try Regex(".*.(jpg|gif|png)")
      let coverArtFilename = fileLines
        .first(where: { $0.wholeMatch(of: coverArtRegex) != nil })
        .map(String.init) ?? "cover.jpg"
      coverArtPath = "\(inputDir)/\(coverArtFilename)"
      print("Cover art path: \(coverArtPath)", verbose: verbose)
    } else {
      throw AMError.osVersion
    }

    // Update audiobook metadata for each audiofile
    for i in 1 ... audiofileCount {
      let fileNumber = String(format: "%0\(filePrefixLength)d", i)
      let filename = "\(fileNumber)\(suffix)"
      let oldFilePath = "\(inputDir)/\(filename).\(`extension`)"
      let newFilePath: String
      if let outputDir = outputDir, outputDir != inputDir {
        newFilePath = "\(outputDir)/\(filename).\(`extension`)"
        // Create directory if a unique output dir is provided
        let mkdirOutput = shell("mkdir -p \(outputDir)").asString
        print(mkdirOutput, verbose: verbose)
      } else {
        newFilePath = "\(inputDir)/\(filename)_new.\(`extension`)"
      }

      // Generate and execute ffmpeg command with updated metadata values
      let updateCommand = [
        "ffmpeg",
        "-y",
        "-i \(oldFilePath)",
        "-i \(coverArtPath)",
        "-map 0",
        "-map 1",
        "-c copy",
        "-metadata album='\(title)'",
        "-metadata artist='\(author)'",
        "-metadata genre='audiobook'",
        "-metadata track='\(fileNumber)'",
        newFilePath,
      ].joined(separator: " ")
      let updateResult = shell(updateCommand)
      if case .success = updateResult {
        print("Conversion Succeeded: ", verbose: verbose)
      } else {
        print("Conversion Failed: ", verbose: verbose)
      }
      print(updateResult.asString, verbose: verbose)

      if outputDir == nil || outputDir == inputDir {
        // Overwrite old file with new file if no new output directory is provided
        shell("mv \(newFilePath) \(oldFilePath)")
      }
    }
  }
}

AudiobookMetadata.main()
