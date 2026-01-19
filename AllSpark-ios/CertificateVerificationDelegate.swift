import Foundation

// MARK: - Certificate Verification Delegate
class CertificateVerificationDelegate: NSObject, URLSessionDelegate {
    let verifyCertificate: Bool

    init(verifyCertificate: Bool) {
        self.verifyCertificate = verifyCertificate
        super.init()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if !verifyCertificate {
            // Skip certificate verification
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            // Use default verification
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
