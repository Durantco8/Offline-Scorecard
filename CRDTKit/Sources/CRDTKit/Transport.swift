import Foundation

public protocol Transport: AnyObject {
    func send(_ data: Data, to peer: DeviceID)
    func broadcast(_ data: Data)
    var onReceive: ((Data, DeviceID) -> Void)? { get set }
}
