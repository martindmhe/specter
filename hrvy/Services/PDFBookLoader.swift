import Foundation
import PDFKit

nonisolated enum PDFBookLoaderError: LocalizedError {
    case unreadable(URL)
    case noText

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            "“\(url.lastPathComponent)” could not be opened as a PDF."
        case .noText:
            "This PDF doesn’t contain selectable text. Scanned books need OCR, which isn’t supported yet."
        }
    }
}

/// Extracts text from a PDF page by page. Synchronous and potentially slow for large
/// books — call it off the main thread.
nonisolated enum PDFBookLoader {
    static func load(from url: URL) throws -> Book {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            throw PDFBookLoaderError.unreadable(url)
        }

        // TODO: OCR — pages whose `string` is empty could be rendered to an image and
        // run through Vision's VNRecognizeTextRequest before tokenizing.
        let pageTexts = (0..<document.pageCount).map { index in
            document.page(at: index)?.string ?? ""
        }

        let book = Book(title: url.lastPathComponent, pageTexts: pageTexts)
        guard !book.words.isEmpty else { throw PDFBookLoaderError.noText }
        return book
    }
}
