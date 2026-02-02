import Foundation
import Testing

@testable import DeltaDoreClient

@Test func gatewayInfoValidator_matchesMacAtTopLevel() {
    let info = TydomGatewayInfo(payload: [
        "mac": .string("aa:bb:cc:dd:ee:ff")
    ])

    let result = TydomGatewayInfoValidator.matchesGateway(
        info: info,
        expectedMac: "AABBCCDDEEFF"
    )

    #expect(result == true)
}

@Test func gatewayInfoValidator_matchesNestedMacKey() {
    let info = TydomGatewayInfo(payload: [
        "gateway": .object([
            "details": .object([
                "gateway_mac": .string("AA-BB-CC-DD-EE-FF")
            ])
        ])
    ])

    let result = TydomGatewayInfoValidator.matchesGateway(
        info: info,
        expectedMac: "aabbccddeeff"
    )

    #expect(result == true)
}

@Test func gatewayInfoValidator_matchesMacInArray() {
    let info = TydomGatewayInfo(payload: [
        "list": .array([
            .object([
                "id": .number(1),
                "macAddress": .string("AABBCCDDEEFF")
            ])
        ])
    ])

    let result = TydomGatewayInfoValidator.matchesGateway(
        info: info,
        expectedMac: "AA:BB:CC:DD:EE:FF"
    )

    #expect(result == true)
}

@Test func gatewayInfoValidator_returnsFalseWhenMissingMac() {
    let info = TydomGatewayInfo(payload: [
        "name": .string("Gateway"),
        "details": .object([
            "serial": .string("123456")
        ])
    ])

    let result = TydomGatewayInfoValidator.matchesGateway(
        info: info,
        expectedMac: "AABBCCDDEEFF"
    )

    #expect(result == false)
}

@Test func gatewayInfoValidator_returnsFalseWhenMacDoesNotMatch() {
    let info = TydomGatewayInfo(payload: [
        "mac": .string("AA:BB:CC:DD:EE:FF")
    ])

    let result = TydomGatewayInfoValidator.matchesGateway(
        info: info,
        expectedMac: "11:22:33:44:55:66"
    )

    #expect(result == false)
}
