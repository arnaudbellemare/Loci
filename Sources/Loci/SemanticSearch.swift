import Accelerate
import NaturalLanguage

enum SemanticSearch {
    static func search(
        query: String,
        in items: [ReferenceItem],
        metadataByID: [ReferenceItem.ID: ReferenceSourceMetadata],
        maxResults: Int = 48
    ) -> [(ReferenceItem, Double)] {
        guard query.count >= 3,
              let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let queryVector = embedding.vector(for: query) else { return [] }

        return items.compactMap { item -> (ReferenceItem, Double)? in
            guard let vector = embedding.vector(for: searchableText(for: item, metadata: metadataByID[item.id])) else { return nil }
            return (item, cosineSimilarity(queryVector, vector))
        }
        .filter { $0.1 >= 0.48 }
        .sorted { $0.1 > $1.1 }
        .prefix(maxResults)
        .map { $0 }
    }

    static func findSimilar(
        to target: ReferenceItem,
        in items: [ReferenceItem],
        metadataByID: [ReferenceItem.ID: ReferenceSourceMetadata],
        maxResults: Int = 16
    ) -> [(ReferenceItem, Double)] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let targetVector = embedding.vector(for: searchableText(for: target, metadata: metadataByID[target.id])) else {
            return lexicalFallback(to: target, in: items, metadataByID: metadataByID, maxResults: maxResults)
        }

        return items.compactMap { candidate -> (ReferenceItem, Double)? in
            guard candidate.id != target.id,
                  let vector = embedding.vector(for: searchableText(for: candidate, metadata: metadataByID[candidate.id])) else {
                return nil
            }
            return (candidate, cosineSimilarity(targetVector, vector))
        }
        .filter { $0.1 >= 0.48 }
        .sorted { $0.1 > $1.1 }
        .prefix(maxResults)
        .map { $0 }
    }

    private static func searchableText(for item: ReferenceItem, metadata: ReferenceSourceMetadata?) -> String {
        [item.title, item.subtitle, metadata?.selectedText, metadata?.articleMarkdown, metadata?.autoTags?.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " · ")
            .prefix(2_000)
            .description
    }

    private static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        vDSP_dotprD(lhs, 1, rhs, 1, &dot, vDSP_Length(lhs.count))
        vDSP_svesqD(lhs, 1, &leftNorm, vDSP_Length(lhs.count))
        vDSP_svesqD(rhs, 1, &rightNorm, vDSP_Length(lhs.count))
        let denominator = sqrt(leftNorm) * sqrt(rightNorm)
        return denominator > 0 ? dot / denominator : 0
    }

    private static func lexicalFallback(
        to target: ReferenceItem,
        in items: [ReferenceItem],
        metadataByID: [ReferenceItem.ID: ReferenceSourceMetadata],
        maxResults: Int
    ) -> [(ReferenceItem, Double)] {
        let targetTerms = terms(in: searchableText(for: target, metadata: metadataByID[target.id]))
        guard !targetTerms.isEmpty else { return [] }
        return items.compactMap { candidate -> (ReferenceItem, Double)? in
            guard candidate.id != target.id else { return nil }
            let candidateTerms = terms(in: searchableText(for: candidate, metadata: metadataByID[candidate.id]))
            let union = targetTerms.union(candidateTerms)
            guard !union.isEmpty else { return nil }
            let score = Double(targetTerms.intersection(candidateTerms).count) / Double(union.count)
            return score > 0 ? (candidate, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxResults)
        .map { $0 }
    }

    private static func terms(in value: String) -> Set<String> {
        Set(value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
    }
}

enum RelatedElementDiscovery {
    static func related(
        to target: ReferenceItem,
        in items: [ReferenceItem],
        metadataByID: [ReferenceItem.ID: ReferenceSourceMetadata],
        limit: Int = 8
    ) async -> [ReferenceItem] {
        async let visual = VisualSearch.relatedItems(to: target, in: items)
        let semantic = SemanticSearch.findSimilar(to: target, in: items, metadataByID: metadataByID)

        var scores: [ReferenceItem.ID: Double] = [:]
        var itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (item, score) in await visual {
            scores[item.id, default: 0] += score * 0.68
        }
        for (item, score) in semantic {
            scores[item.id, default: 0] += score * 0.32
        }
        itemsByID.removeValue(forKey: target.id)
        return scores.sorted { $0.value > $1.value }.prefix(limit).compactMap { itemsByID[$0.key] }
    }
}
