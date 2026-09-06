import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// USDA FoodData Central — the free, authoritative nutrition database.
/// https://fdc.nal.usda.gov/api-guide.html
///
/// Only the Foundation and SR Legacy datasets are searched: they are
/// generic foods with lab-measured values, which is what a recipe
/// ingredient is. The Branded dataset is noisy and skipped.
public struct USDAFoodDataClient: NutrientSource {
    public var apiKey: String
    public var session: URLSession
    public var endpoint: URL

    public init(
        apiKey: String,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
    }

    public func lookup(_ query: String) async throws -> FoodNutrients? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy"),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await session.proportionData(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw USDAError.httpStatus(http.statusCode)
        }
        return try Self.parse(data)
    }

    public enum USDAError: Error, Equatable {
        case httpStatus(Int)
    }

    // MARK: Response parsing

    struct SearchResponse: Decodable {
        var foods: [Food]
    }

    struct Food: Decodable {
        var fdcId: Int
        var description: String
        var foodNutrients: [Nutrient]
    }

    struct Nutrient: Decodable {
        var nutrientId: Int?
        var nutrientNumber: String?
        var value: Double?
    }

    /// Nutrient identifiers per FoodData Central: protein 1003 (#203),
    /// total fat 1004 (#204), carbohydrate by difference 1005 (#205).
    static func parse(_ data: Data) throws -> FoodNutrients? {
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        for food in decoded.foods {
            var protein: Double?
            var fat: Double?
            var carbs: Double?
            for nutrient in food.foodNutrients {
                let key = nutrient.nutrientId.map(String.init) ?? nutrient.nutrientNumber ?? ""
                switch key {
                case "1003", "203": protein = nutrient.value
                case "1004", "204": fat = nutrient.value
                case "1005", "205": carbs = nutrient.value
                default: break
                }
            }
            if protein != nil || fat != nil || carbs != nil {
                return FoodNutrients(
                    description: food.description,
                    sourceID: String(food.fdcId),
                    per100g: Macros(protein: protein ?? 0, fat: fat ?? 0, carbs: carbs ?? 0))
            }
        }
        return nil
    }
}

extension URLSession {
    /// Completion-handler bridge that works on every platform's Foundation.
    func proportionData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}
