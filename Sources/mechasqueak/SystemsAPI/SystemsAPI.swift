/*
 Copyright 2020 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import AsyncHTTPClient
import IRCKit

class SystemsAPI {
    static func performSearch (
        forSystem systemName: String,
        onComplete: @escaping (SystemsAPISearchDocument) -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        var url = URLComponents(string: "https://sapi.fuelrats.dev/mecha")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    let searchResult = try! decoder.decode(
                        SystemsAPISearchDocument.self,
                        from: Data(buffer: response.body!)
                    )
                    onComplete(searchResult)
                case .failure(let restError):
                    onError(restError)
            }
        }
    }

    static func performSearchAndLandmarkCheck (
        forSystem systemName: String,
        onComplete: @escaping (
            SystemsAPISearchDocument.SearchResult?,
            SystemsAPILandmarkDocument.LandmarkResult?,
            String?
        ) -> Void) {
        self.performSearch(forSystem: systemName, onComplete: { systemSearch in
            guard let result = systemSearch.data.first(where: {
                $0.similarity == 1
            }) else {
                onComplete(nil, nil, Autocorrect.check(system: systemName, search: systemSearch)?.uppercased())
                return
            }

            self.performLandmarkCheck(forSystem: result.name, onComplete: { landmarkSearch in
                guard let landmarkResult = landmarkSearch.landmarks.first else {
                    onComplete(result, nil, nil)
                    return
                }

                onComplete(result, landmarkResult, nil)
            }, onError: { _ in
                onComplete(result, nil, nil)
            })
        }, onError: { _ in
            onComplete(nil, nil, nil)
        })
    }

    static func performLandmarkCheck (
        forSystem systemName: String,
        onComplete: @escaping (SystemsAPILandmarkDocument) -> Void, onError: @escaping (Error?) -> Void) {
        var url = URLComponents(string: "https://sapi.fuelrats.dev/landmark")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    do {
                        let searchResult = try decoder.decode(
                            SystemsAPILandmarkDocument.self,
                            from: Data(buffer: response.body!)
                        )
                        onComplete(searchResult)
                    } catch let error {
                        onError(error)
                    }
                case .failure(let restError):
                    onError(restError)
            }
        }
    }

    static func performStatisticsQuery (
        onComplete: @escaping (SystemsAPIStatisticsDocument) -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        let url = URLComponents(string: "https://sapi.fuelrats.dev/api/stats")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    do {
                        let result = try decoder.decode(
                            SystemsAPIStatisticsDocument.self,
                            from: Data(buffer: response.body!)
                        )
                        onComplete(result)
                    } catch let error {
                        print(String(describing: error))
                        onError(error)
                    }
                case .failure(let restError):
                    onError(restError)
            }
        }
    }
}

struct SystemsAPISearchDocument: Codable {
    let meta: Meta
    let data: [SearchResult]

    struct Meta: Codable {
        let name: String
        let type: String
    }

    struct SearchResult: Codable {
        let name: String
        let id64: Int64

        let similarity: Double?
        let distance: Int?
        let permitRequired: Bool
        let permitName: String?

        var searchSimilarityText: String {
            if let distance = self.distance {
                return String(distance)
            } else if let similarity = self.similarity {
                return "\(String(Int(similarity * 100)))%"
            } else {
                return "?"
            }
        }

        var permitText: String? {
            if self.permitRequired {
                if let permitName = self.permitName {
                    return IRCFormat.color(.LightRed, "(\(permitName) Permit Required)")
                } else {
                    return IRCFormat.color(.LightRed, "Permit Required)")
                }
            }
            return nil
        }

        var textRepresentation: String {
            if self.permitRequired {
                if let permitName = self.permitName {
                    let permitReq = IRCFormat.color(.LightRed, "(\(permitName) Permit Required)")
                    return "\"\(self.name)\" [\(self.searchSimilarityText)] \(permitReq)"
                }
                let permitReq = IRCFormat.color(.LightRed, "(Permit Required)")
                return "\"\(self.name)\" [\(self.searchSimilarityText)] \(permitReq)"
            }
            return "\"\(self.name)\" [\(self.searchSimilarityText)]"
        }
    }
}

struct SystemsAPILandmarkDocument: Codable {
    let meta: Meta
    let landmarks: [LandmarkResult]

    struct Meta: Codable {
        let name: String
    }

    struct LandmarkResult: Codable {
        let name: String
        let distance: Double
    }
}

struct SystemsAPIStatisticsDocument: Codable {
    struct SystemsAPIStatistic: Codable {
        struct SystemsAPIStatisticAttributes: Codable {
            let syscount: Int64
            let starcount: Int64
            let bodycount: Int64
        }

        let id: String
        let type: String
        let attributes: SystemsAPIStatisticAttributes
    }

    let data: [SystemsAPIStatistic]
}
