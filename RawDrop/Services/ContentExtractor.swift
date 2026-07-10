import Foundation
import PDFKit
import CryptoKit
import UniformTypeIdentifiers

enum ContentExtractor {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Extract plain text suitable for LLM compile. Never mutates the source file.
    static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if type?.conforms(to: .pdf) == true || ext == "pdf" {
            return try extractPDF(url)
        }

        if type?.conforms(to: .image) == true {
            return """
            [Image source]
            Filename: \(url.lastPathComponent)
            Path: \(url.path)
            Note: Binary image. Compile from filename and any surrounding context only.
            """
        }

        // HTML (dragged .html / .htm files) — keep raw on disk; convert only for compile.
        if ext == "html" || ext == "htm" || type?.conforms(to: .html) == true {
            if let html = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                return HTMLTextExtractor.toMarkdown(html, sourceLabel: url.lastPathComponent)
            }
        }

        // Text-like (including .md, .txt, and html mislabeled)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            if HTMLTextExtractor.looksLikeHTML(string: text) {
                return HTMLTextExtractor.toMarkdown(text, sourceLabel: url.lastPathComponent)
            }
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            if HTMLTextExtractor.looksLikeHTML(string: text) {
                return HTMLTextExtractor.toMarkdown(text, sourceLabel: url.lastPathComponent)
            }
            return text
        }

        return """
        [Binary or unreadable source]
        Filename: \(url.lastPathComponent)
        Extension: \(ext)
        Note: Could not extract text. Summarize from filename only.
        """
    }

    private static func extractPDF(_ url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            return "[PDF unreadable: \(url.lastPathComponent)]"
        }
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string {
                parts.append(s)
            }
        }
        let text = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "[PDF has no extractable text: \(url.lastPathComponent)]"
        }
        return text
    }

    static func chunk(_ text: String, maxChars: Int = 3500) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxChars else {
            return cleaned.isEmpty ? [] : [cleaned]
        }
        var chunks: [String] = []
        var start = cleaned.startIndex
        while start < cleaned.endIndex {
            let end = cleaned.index(start, offsetBy: maxChars, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            var sliceEnd = end
            if end < cleaned.endIndex {
                // try to break on paragraph
                let window = cleaned[start..<end]
                if let breakRange = window.range(of: "\n\n", options: .backwards) {
                    sliceEnd = breakRange.upperBound
                } else if let space = window.range(of: " ", options: .backwards) {
                    sliceEnd = space.upperBound
                }
            }
            let piece = String(cleaned[start..<sliceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                chunks.append(piece)
            }
            start = sliceEnd
        }
        return chunks
    }
}
