import Foundation

extension ProjectXService {

    func searchContracts(text: String, live: Bool = false) async -> [Contract] {
        guard let token = sessionToken else { return [] }
        let body = ContractSearchRequest(searchText: text, live: live)
        guard let response: ContractSearchResponse = await post(
            path: "/api/Contract/search", body: body, token: token
        ) else { return [] }
        let contracts = response.contracts ?? []
        cacheContractNames(contracts)
        return contracts
    }

    func contractById(_ contractId: String) async -> Contract? {
        guard let token = sessionToken else { return nil }
        let body = ContractByIdRequest(contractId: contractId)
        guard let response: ContractByIdResponse = await post(
            path: "/api/Contract/searchById", body: body, token: token
        ) else { return nil }
        if let c = response.contract { cacheContractNames([c]) }
        return response.contract
    }

    func availableContracts(live: Bool = false) async -> [Contract] {
        guard let token = sessionToken else { return [] }
        let body = AvailableContractsRequest(live: live)
        guard let response: ContractSearchResponse = await post(
            path: "/api/Contract/available", body: body, token: token
        ) else { return [] }
        let contracts = response.contracts ?? []
        cacheContractNames(contracts)
        return contracts
    }

    func retrieveBars(
        contractId: String,
        live: Bool = false,
        startTime: Date,
        endTime: Date,
        unit: BarUnit = .hour,
        unitNumber: Int = 1,
        limit: Int = 500,
        includePartialBar: Bool = false
    ) async -> [Bar] {
        guard let token = sessionToken else { return [] }
        let fmt = ISO8601DateFormatter()
        let body = RetrieveBarsRequest(
            contractId:        contractId,
            live:              live,
            startTime:         fmt.string(from: startTime),
            endTime:           fmt.string(from: endTime),
            unit:              unit.rawValue,
            unitNumber:        unitNumber,
            limit:             min(limit, 20_000),
            includePartialBar: includePartialBar
        )
        guard let response: RetrieveBarsResponse = await post(
            path: "/api/History/retrieveBars", body: body, token: token
        ) else { return [] }
        return response.bars ?? []
    }
}
