import SensiAuraKeys

let keys = SensiAuraKeys()

Task {
    do {
        try await keys.initialize()
        let license = try await keys.login(withLicense: "LICENCIA_DEL_USUARIO")
        print("Acceso válido: \(license.expiry?.description ?? "sin fecha")")
    } catch {
        print("Acceso denegado: \(error.localizedDescription)")
    }
}