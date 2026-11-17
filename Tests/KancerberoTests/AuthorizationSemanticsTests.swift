import Foundation
import Security

/// Verifies the daemon's critical assumption: a 32-byte external form created
/// without rights cannot authorize system.privilege.admin unless the right was
/// preauthorized. Run as the normal user and with sudo; neither must prompt.
@main
enum AuthorizationSemanticsTests {
    static func main() {
        var authRef: AuthorizationRef?
        let created = AuthorizationCreate(nil, nil, [], &authRef)
        precondition(created == errAuthorizationSuccess,
                     "AuthorizationCreate failed: \(created)")
        guard let authRef else {
            preconditionFailure("missing AuthorizationRef")
        }
        defer { AuthorizationFree(authRef, []) }

        var form = AuthorizationExternalForm()
        let made = AuthorizationMakeExternalForm(authRef, &form)
        precondition(made == errAuthorizationSuccess,
                     "AuthorizationMakeExternalForm failed: \(made)")
        let data = withUnsafeBytes(of: &form.bytes) { Data($0) }
        precondition(data.count == 32, "external form must be 32 bytes")

        var reconstructed = AuthorizationExternalForm()
        data.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &reconstructed.bytes) { destination in
                destination.copyMemory(from: source)
            }
        }
        var internalRef: AuthorizationRef?
        let internalized = AuthorizationCreateFromExternalForm(&reconstructed,
                                                               &internalRef)
        precondition(internalized == errAuthorizationSuccess,
                     "AuthorizationCreateFromExternalForm failed: \(internalized)")
        guard let internalRef else {
            preconditionFailure("missing internal AuthorizationRef")
        }
        defer { AuthorizationFree(internalRef, []) }

        let rightName = "system.privilege.admin"
        let status: OSStatus = rightName.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0,
                                         value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                var authorizedPointer: UnsafeMutablePointer<AuthorizationRights>?
                let status = AuthorizationCopyRights(internalRef, &rights, nil, [],
                                                     &authorizedPointer)
                if let authorizedPointer {
                    _ = AuthorizationFreeItemSet(authorizedPointer)
                }
                return status
            }
        }
        precondition(status != errAuthorizationSuccess,
                     "an un-preauthorized right was granted (status \(status))")
        print("AuthorizationSemanticsTests: ok (status \(status))")
    }
}
