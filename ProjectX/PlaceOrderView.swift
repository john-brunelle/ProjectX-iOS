import SwiftUI

struct PlaceOrderView: View {
    @Environment(ProjectXService.self) var service
    @Environment(\.dismiss) var dismiss

    let contract: Contract

    @State private var selectedAccount:  Account?
    @State private var orderType:        OrderType  = .market
    @State private var orderSide:        OrderSide  = .bid
    @State private var size                         = 1
    @State private var limitPrice                   = ""
    @State private var stopPrice                    = ""
    @State private var trailPrice                   = ""
    @State private var useStopLoss                  = false
    @State private var stopLossTicks                = 10
    @State private var stopLossType:     OrderType  = .stop
    @State private var useTakeProfit                = false
    @State private var takeProfitTicks              = 20
    @State private var takeProfitType:   OrderType  = .limit
    @State private var isSubmitting                 = false
    @State private var resultMessage                = ""
    @State private var showResult                   = false

    var needsLimitPrice: Bool { orderType == .limit }
    var needsStopPrice:  Bool { orderType == .stop  }
    var needsTrailPrice: Bool { orderType == .trailingStop }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contract") {
                    HStack {
                        Text(contract.name).font(.headline)
                        Spacer()
                        Text(contract.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Account") {
                    if service.accounts.isEmpty {
                        Text("No accounts loaded").foregroundStyle(.secondary)
                    } else {
                        Picker("Account", selection: $selectedAccount) {
                            ForEach(service.accounts) { acct in
                                Text(acct.name).tag(Optional(acct))
                            }
                        }
                    }
                }

                Section("Order") {
                    Picker("Type", selection: $orderType) {
                        ForEach(OrderType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    Picker("Side", selection: $orderSide) {
                        ForEach(OrderSide.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Size: \(size)", value: $size, in: 1...100)
                }

                if needsLimitPrice || needsStopPrice || needsTrailPrice {
                    Section("Price") {
                        if needsLimitPrice {
                            HStack {
                                Text("Limit Price")
                                Spacer()
                                TextField("0.00", text: $limitPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                        }
                        if needsStopPrice {
                            HStack {
                                Text("Stop Price")
                                Spacer()
                                TextField("0.00", text: $stopPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                        }
                        if needsTrailPrice {
                            HStack {
                                Text("Trail Price")
                                Spacer()
                                TextField("0.00", text: $trailPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                        }
                    }
                }

                Section("Stop Loss") {
                    Toggle("Stop Loss Bracket", isOn: $useStopLoss)
                    if useStopLoss {
                        Stepper("Ticks: \(stopLossTicks)", value: $stopLossTicks, in: 1...500)
                        Picker("Type", selection: $stopLossType) {
                            ForEach([OrderType.stop, .trailingStop, .market]) { t in
                                Text(t.label).tag(t)
                            }
                        }
                    }
                }

                Section("Take Profit") {
                    Toggle("Take Profit Bracket", isOn: $useTakeProfit)
                    if useTakeProfit {
                        Stepper("Ticks: \(takeProfitTicks)", value: $takeProfitTicks, in: 1...500)
                        Picker("Type", selection: $takeProfitType) {
                            ForEach([OrderType.limit, .market]) { t in
                                Text(t.label).tag(t)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await submitOrder() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() }
                            else {
                                Text("Place \(orderSide.label) Order")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(orderSide == .bid ? .green : .red)
                            }
                            Spacer()
                        }
                    }
                    .disabled(selectedAccount == nil || isSubmitting)
                }
            }
            .navigationTitle("Place Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { selectedAccount = service.activeAccount }
            .alert(resultMessage, isPresented: $showResult) {
                Button("OK") {
                    if resultMessage.hasPrefix("✅") { dismiss() }
                }
            }
        }
    }

    private func submitOrder() async {
        guard let account = selectedAccount else { return }
        isSubmitting = true
        let sl = useStopLoss   ? BracketOrder(ticks: stopLossTicks,   type: stopLossType.rawValue)   : nil
        let tp = useTakeProfit ? BracketOrder(ticks: takeProfitTicks, type: takeProfitType.rawValue) : nil
        let orderId = await service.placeOrder(
            accountId:  account.id,
            contractId: contract.id,
            type:       orderType,
            side:       orderSide,
            size:       size,
            limitPrice: Double(limitPrice),
            stopPrice:  Double(stopPrice),
            trailPrice: Double(trailPrice),
            stopLoss:   sl,
            takeProfit: tp
        )
        isSubmitting = false
        resultMessage = orderId != nil ? "✅ Order placed! ID: \(orderId!)" : "❌ \(service.errorMessage ?? "Order failed")"
        showResult = true
    }
}
