//
//  ViewController.swift
//  SwiftVideoPlayer
//
//  Created by Ivo Vacek on 05/05/16.
//  Copyright © 2016 Ivo Vacek. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation


class ViewController: UIViewController, AVPlayerViewControllerDelegate, AVAssetResourceLoaderDelegate {

    var videoUrl: NSURL!
    var videoAsset: AVURLAsset!
    let queue = dispatch_queue_create("delegate", DISPATCH_QUEUE_SERIAL)

    var key: Rabbit.Key?
    var nonce: Rabbit.IV?
    var decryptor: ([UInt8]->[UInt8])?

    let nonceSize = Int64(sizeof(Rabbit.IV.self))
    var blockNumber: Int64 = 0  // current block to process
    var blockSize: Int64 = 0    // size of (nonce + payload)
    var headerSize: Int64 = 0   // size of (headerSizeInfo + blockSizeInfo + metaData)
    var blockCount: Int64 = 0   // must be calculated and checked
    
    @IBOutlet weak var playEncryptedButton: UIButton!
    @IBOutlet weak var log: UITextView!

    @IBAction func playVideo(sender: UIButton) {
        // free sample from from http://www.sample-videos.com
        videoUrl = NSBundle.mainBundle().URLForResource("big_buck_bunny_360p_50mb", withExtension: "mp4")!
        performSegueWithIdentifier("seguePlayVideo", sender: self)
    }

    @IBAction func encrypt(sender: UIButton) {
        self.playEncryptedButton.enabled = false
        // clear log
        self.log.text = ""
        // WARNING !!! Don't do this in main thread

        let queue = dispatch_queue_create("encrypt", DISPATCH_QUEUE_SERIAL)
        dispatch_async(queue) {
            func log(txt: String) {
                dispatch_async(dispatch_get_main_queue()) {
                    self.log.text.appendContentsOf(txt)
                    self.log.font = UIFont(name: "Menlo-Bold", size: 11.0)!
                    let c = self.log.text.characters.count
                    if  c > 0 {
                        let bottom = NSMakeRange(c - 1, 1)
                        self.log.scrollRangeToVisible(bottom)
                    }
                }
            }
            // encryption 'secret'

            let key: Rabbit.Key = s2K("0F62B5085BAE0154A7FA4DA0F34699EC")

            var encrypted = NSHomeDirectory()
            encrypted.appendContentsOf("/Documents/encrypted.dat")

            // free sample for testing from http://www.sample-videos.com
            //
            // (1) encryption time depends on size of the file (it is really fast and smooth proces)
            // (2) size and content of a file which you would like to encrypt
            //     is limited only by your time and disk space :-)
            // (3) 3 GB full HD video could be encrypted and then played (real time decription)
            //     very easy on mac book late 2008 simulator or first iPad mini retina
            // (4) use release builds for performance testing and working with big files!
            // (5) for debugging purpose use smal sized video and small block size

            let normal = NSBundle.mainBundle().pathForResource("big_buck_bunny_360p_50mb", ofType: "mp4")!

            let fr = FStream(path: normal, mode: "r")
            let fw = FStream(path: encrypted, mode: "w")

            // all data in container are in big endian (network) byte order
            //
            // offset | size | data
            // ------------------------------------------------------------
            //      0 |     2 | 16 bit header size (HS)
            //      2 |     3 | 24 bit block size  (BS)
            //      5 |   any | meta data, actual size is header size - 5
            // -------------------------------------------------------------
            //     HS |    16 | nonce (initial vector for stream decoder)
            //  HS+16 | BS-16 | any pay load data (encrypted)
            // -------------------------------------------------------------
            // ..... others blocks as necesary
            // -------------------------------------------------------------
            // N*BS+5 |    16 | last nonce
            // N*BS+21|   LBS | LBS (last block size) 0..<(BS-16)
            // EOF
            //
            // NOTE: (1) N represent number of blocks
            //       (2) all blocks (except tha last one) have the same size
            //       (3) only payload data are encrypted

            let metaData = Array("some meta data".utf8)

            // NOTE: (1) max blockSize is 2^24 - 1 (16 MB)
            //       (2) optimal value depends on your needs
            //       (3) it is NOT critical parameter, general value cca 1MB will almost work
            //       (4) very small values increase to much resulting container
            //           and could lead to unplayable video (you can still decrypt it)
            // TIP:  use small BS when debugging!

            let blockSize = 1024 * 1024 // 1024 KB
            let blockSizeData = [
                UInt8(blockSize & 0xff),
                UInt8((blockSize & 0xff00) >> 8),
                UInt8((blockSize & 0xff0000) >> 16)
            ]

            let headerSize = 2 + blockSizeData.count + metaData.count
            let headerSizeData = [
                UInt8(headerSize & 0xff),
                UInt8((headerSize & 0xff00) >> 8)
            ]

            // write header, not encrypted
            guard fw.write(headerSizeData) == true &&
                fw.write(blockSizeData) &&
                fw.write(metaData) else {
                    log("error to write header\n")
                    return
            }

            func rndNonce()->(nonce: Rabbit.IV, bytes:[UInt8]) {
                let byteCount = sizeof(Rabbit.IV.self)
                let buffer = UnsafeMutablePointer<UInt8>.alloc(byteCount)
                defer { buffer.destroy(byteCount) }
                arc4random_buf(buffer, byteCount)
                var bytes: [UInt8] = []
                for i in 0..<byteCount {
                    bytes.append((buffer + i).memory)
                }
                let nonce = (UnsafePointer<UInt32>(buffer).memory, UnsafePointer<UInt32>(buffer + sizeof(UInt32.self)).memory)
                return (nonce: nonce, bytes: bytes)
            }

            // encrypt sample video
            // variable block is NOT part of encryption routine

            var block = 0
            let start = NSDate()
            log("wait, encrypting sample video ...\n")
            repeat {

                let nonce = rndNonce()

                // create and write one block
                if let data = fr.read(blockSize - nonce.bytes.count) where !data.isEmpty {
                    fw.write(nonce.bytes) // not encrypted !!!
                    let encryptor = cryptGenerator(key, iv: nonce.nonce, offset: 0)
                    guard fw.write(encryptor(data)) == true else {
                        log("error to write data\n")
                        return
                    }
                } else {
                    break
                }
                log("nonce: \(nonce.bytes.hex) block: \(block)\n")
                block += 1
            } while true
            let time = NSDate().timeIntervalSinceDate(start)
            log("encrypted: \(encrypted) in: \(time) seconds\n")
            log("\n")
            dispatch_async(dispatch_get_main_queue(), {
                self.playEncryptedButton.enabled = true
            })
        }

    }

    @IBAction func playEncryptedVideo(sender: UIButton) {
        videoUrl = NSURL(string: "encrypted:///encrypted.dat;public.mpeg-4")
        performSegueWithIdentifier("seguePlayVideo", sender: self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "seguePlayVideo" {
            let destination = segue.destinationViewController as! AVPlayerViewController
            videoAsset = AVURLAsset(URL: videoUrl)

            videoAsset.resourceLoader.setDelegate(self, queue: queue)
            let item = AVPlayerItem(asset: videoAsset)
            destination.player = AVPlayer(playerItem: item)
        }
        
    }
    
    // MARK: - AVAssetResourceLoderDelegate

    func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        func log(txt: String) {
            dispatch_async(dispatch_get_main_queue()) {
                self.log.text.appendContentsOf(txt)
                self.log.font = UIFont(name: "Menlo-Bold", size: 11.0)!
                let c = self.log.text.characters.count
                if  c > 0 {
                    let bottom = NSMakeRange(c - 1, 1)
                    self.log.scrollRangeToVisible(bottom)
                }
            }
        }

        // preconditions
        guard let url = loadingRequest.request.URL where url.scheme == "encrypted" else {
            log("error: no url with scheme 'encrypred'\n")
            return false
        }
        guard let path = url.path else {
            log("error: no path\n")
            return false
        }
        guard let type = url.parameterString /* where .... check type here */else {
            log("error: unknown media UTI\n")
            return false
        }

        // encrypted file path
        var encrypted = NSHomeDirectory()
        encrypted.appendContentsOf("/Documents")
        encrypted.appendContentsOf(path)

        // stream for reading encrypted data
        let fr = FStream(path: encrypted, mode: "r")

        if let contentRequest = loadingRequest.contentInformationRequest {

            // all data in container are in big endian (network) byte order
            //
            // offset | size | data
            // ------------------------------------------------------------
            //      0 |     2 | 16 bit header size (HS)
            //      2 |     3 | 24 bit block size  (BS)
            //      5 |   any | meta data, actual size is header size - 5
            // -------------------------------------------------------------
            //     HS |    16 | nonce (initial vector for stream decoder)
            //  HS+16 | BS-16 | any pay load data (encrypted)
            // -------------------------------------------------------------
            // ..... others blocks as necesary
            // -------------------------------------------------------------
            // N*BS+5 |    16 | last nonce
            // N*BS+21|   LBS | LBS (last block size) 0..<(BS-16)
            // EOF
            //
            // NOTE: (1) N represent number of blocks
            //       (2) all blocks (except tha last one) have the same size
            //       (3) only payload data are encrypted


            if headerSize == 0 {
                fr.seek(0)
                if let header = fr.read(5) {
                    headerSize = Int64(header[0])
                    headerSize += Int64(header[1]) << 8
                    blockSize = Int64(header[2])
                    blockSize += Int64(header[3]) << 8
                    blockSize += Int64(header[4]) << 16
                }
                if let meta = fr.read(Int(headerSize) - 5) {
                    let metadata = UTF8.decode(meta)
                    log("header: (size: \(headerSize), block size: \(blockSize), meta data: \(metadata))\n")
                } else {
                    log("error: error to read from container\n")
                }
            }

            // use the same 'secret' as for encryption
            // MARK: should be based on some user input

            key = key ?? s2K("0F62B5085BAE0154A7FA4DA0F34699EC")

            let size = fr.size()
            blockCount = (size - headerSize) / blockSize

            let containerSize = blockCount * nonceSize + headerSize
            contentRequest.contentLength = size - containerSize

            // must be proper UTI !!!!!!! ( "video/mp4" is NOT valid UTI !!!)
            contentRequest.contentType = type
            contentRequest.byteRangeAccessSupported = true

            log("block count: \(blockCount) file size: \(size) content size: \(size - containerSize)\n")
        }

        if let dataRequest = loadingRequest.dataRequest {
            // use this for decryptor set up !! (payload space)
            let requestedOffset = dataRequest.requestedOffset // content offset

            // need to calculate from where and how much we can read in this data request
            blockNumber = requestedOffset / (blockSize - nonceSize)

            // file positions (where to read from encrypted container)
            let nonceOffset = headerSize + blockNumber * blockSize
            let dataOffset = requestedOffset + blockNumber * nonceSize + headerSize + nonceSize
            let maxDataCount = nonceOffset + blockSize - dataOffset

            // reposition in file and read the current block's nonce
            fr.seek(nonceOffset)
            if let nonceData = fr.read(Int(nonceSize)) {
                let nonce = s2IV(nonceData.hex)
                // offset must be in payload space in current block
                decryptor = cryptGenerator(key, iv: nonce, offset: requestedOffset - blockNumber * (blockSize - nonceSize))
            } else {
                log("error: invalid nonce\n")
                return false
            }

            let requestedLength = dataRequest.requestedLength

            // all decrypted data must be in the same block!
            let chunkSize = min(requestedLength, Int(maxDataCount))
            // seek in file to proper position corresponding to requestedOffset in payload
            fr.seek(dataOffset)
            if let encrypted = fr.read(chunkSize) where !encrypted.isEmpty {
                if let decrypted = decryptor?(encrypted) {
                    dataRequest.respondWithData(NSData(bytes: decrypted, length: decrypted.count))
                    loadingRequest.finishLoading()
                } else {
                    log("error: invalid decryptor\n")
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
}

