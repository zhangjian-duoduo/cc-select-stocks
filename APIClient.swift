import Foundation

/// 统一的 API 客户端，处理鉴权、重试、超时
struct APIClient {
    static let baseURL = AppConfig.baseURL
    static let apiKey = AppConfig.apiKey

    enum APIError: LocalizedError {
        case urlError
        case serverError(Int)
        case decodingError(Error)
        case networkError(Error)
        case timeout

        var errorDescription: String? {
            switch self {
            case .urlError: return "URL 构造错误"
            case .serverError(let code): return "服务器错误 (\(code))"
            case .decodingError(let err): return "数据解析失败: \(err.localizedDescription)"
            case .networkError(let err): return "网络错误: \(err.localizedDescription)"
            case .timeout: return "请求超时，请重试"
            }
        }
    }

    /// 带重试的 GET 请求
    static func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        retries: Int = 3,
        timeout: TimeInterval = 30
    ) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIError.urlError
        }

        return try await request(url: url, retries: retries, timeout: timeout)
    }

    /// 带重试的 POST 请求
    static func post<T: Decodable>(
        _ path: String,
        body: [String: Any],
        retries: Int = 3,
        timeout: TimeInterval = 180
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.urlError
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        urlRequest.timeoutInterval = timeout
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return try await performRequest(urlRequest, retries: retries)
    }

    /// 无重试的快速请求（用于非关键数据）
    static func getQuick<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 15
    ) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIError.urlError
        }

        return try await request(url: url, retries: 0, timeout: timeout)
    }

    /// 返回原始 Data，用于自定义解析（如 StockAPI.parseDetailResponse）
    static func getData(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        retries: Int = 2,
        timeout: TimeInterval = 30
    ) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIError.urlError
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        urlRequest.timeoutInterval = timeout

        var lastError: Error?
        for attempt in 0...retries {
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.serverError(0)
                }
                if httpResponse.statusCode == 403 {
                    throw APIError.serverError(403)
                }
                guard httpResponse.statusCode == 200 else {
                    throw APIError.serverError(httpResponse.statusCode)
                }
                return data
            } catch is CancellationError {
                throw APIError.timeout
            } catch let error as APIError {
                lastError = error
                if case .serverError = error { throw error }
            } catch {
                lastError = APIError.networkError(error)
            }
            if attempt < retries {
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }
        throw lastError ?? APIError.timeout
    }

    // MARK: - Private

    private static func request<T: Decodable>(
        url: URL,
        retries: Int,
        timeout: TimeInterval = 30
    ) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        urlRequest.timeoutInterval = timeout

        return try await performRequest(urlRequest, retries: retries)
    }

    private static func performRequest<T: Decodable>(
        _ urlRequest: URLRequest,
        retries: Int
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0...retries {
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.serverError(0)
                }

                if httpResponse.statusCode == 403 {
                    throw APIError.serverError(403)
                }

                guard httpResponse.statusCode == 200 else {
                    throw APIError.serverError(httpResponse.statusCode)
                }

                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw APIError.decodingError(error)
                }
            } catch is CancellationError {
                throw APIError.timeout
            } catch let error as APIError {
                lastError = error
                // 服务器错误不重试
                if case .serverError = error { throw error }
                if case .decodingError = error { throw error }
            } catch {
                lastError = APIError.networkError(error)
            }

            // 退避重试
            if attempt < retries {
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }

        throw lastError ?? APIError.timeout
    }
}
