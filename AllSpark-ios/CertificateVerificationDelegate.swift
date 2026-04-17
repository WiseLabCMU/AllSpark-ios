import Foundation

// MARK: - Certificate Verification Delegate
// NOTE (post-beta): Consider implementing certificate pinning to the
// AllSpark server's specific certificate before deploying over public
// networks. The current implementation either trusts everything or
// uses the system's default trust evaluation.
class CertificateVerificationDelegate: NSObject, URLSessionDelegate {
    let verifyCertificate: Bool

    init(verifyCertificate: Bool) {
        self.verifyCertificate = verifyCertificate
        super.init()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !verifyCertificate,
           let trust = challenge.protectionSpace.serverTrust {
            // Skip certificate verification
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            // Use default verification
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
