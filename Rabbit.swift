//
//  rabbit.swift
//  sqrtrnd
//
//  Created by Ivo Vacek on 11/04/16.
//  Copyright © 2016 Ivo Vacek. All rights reserved.
//

class Rabbit {
    typealias Vect = (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    static let vect0: Vect = (0,0,0,0,0,0,0,0)

    typealias State = (x: Vect, c: Vect, carry: UInt32)
    static let state0: State = (x: vect0, c: vect0, carry: 0)

    typealias Key = (UInt32, UInt32, UInt32, UInt32)
    static let key0: Key = (0,0,0,0)
    typealias IV = (UInt32,UInt32)
    static let iv0: IV = (0,0)

    typealias Ctx = (master: State, work: State)
    var ctx: Ctx = (master: state0, work: state0)

    private var byteStream: [UInt8] = []

    init() {}

    init(key: Key, iv: IV = Rabbit.iv0) {
        keySetup(key)
        ivSetup(iv)
    }

    private let rabbitG  = { (p: UInt32)->UInt32 in
        let p = UInt64(p)
        let t2 = p * p
        let r = t2 ^ (t2 >> 32)
        return UInt32(truncatingBitPattern: r)//UInt32(r % 0x1_0000_0000)
    }

    func keySetup(key: Key) {

        // setup initial state
        ctx.master.x.0 = key.0
        ctx.master.x.2 = key.1
        ctx.master.x.4 = key.2
        ctx.master.x.6 = key.3
        ctx.master.x.1 = key.3 << 16 | key.2 >> 16
        ctx.master.x.3 = key.0 << 16 | key.3 >> 16
        ctx.master.x.5 = key.1 << 16 | key.0 >> 16
        ctx.master.x.7 = key.2 << 16 | key.1 >> 16

        ctx.master.c.0 = key.2 << 16 | key.2 >> 16
        ctx.master.c.2 = key.3 << 16 | key.3 >> 16
        ctx.master.c.4 = key.0 << 16 | key.0 >> 16
        ctx.master.c.6 = key.1 << 16 | key.1 >> 16
        ctx.master.c.1 = (key.0 & 0xFFFF_0000) | (key.1 & 0xFFFF)
        ctx.master.c.3 = (key.1 & 0xFFFF_0000) | (key.2 & 0xFFFF)
        ctx.master.c.5 = (key.2 & 0xFFFF_0000) | (key.3 & 0xFFFF)
        ctx.master.c.7 = (key.3 & 0xFFFF_0000) | (key.0 & 0xFFFF)

        ctx.master.carry = 0

        // iterate system master ctx 4 times
        (0..<4).forEach {_ in
            nextState(master: true)
        }

        // Modify the counters
        //
        ctx.master.c.0 ^= ctx.master.x.4
        ctx.master.c.1 ^= ctx.master.x.5
        ctx.master.c.2 ^= ctx.master.x.6
        ctx.master.c.3 ^= ctx.master.x.7
        ctx.master.c.4 ^= ctx.master.x.0
        ctx.master.c.5 ^= ctx.master.x.1
        ctx.master.c.6 ^= ctx.master.x.2
        ctx.master.c.7 ^= ctx.master.x.3

        // copy master to work (x,c,carry)
        ctx.work = ctx.master
        byteStream = []

    }

    func ivSetup(iv: IV) {
        let v = (
            iv.0,                                           // IV[31..0]
            (iv.1 & 0xFFFF_0000) | (iv.0 >> 16 & 0xFFFF),   // (IV[63..48] || IV[31..16])
            iv.1,                                           // IV[63..32]
            iv.1 << 16 | (iv.0 & 0x0000_FFFF)               // (IV[47..32] || IV[15..0])
        )

        // mofify the counters
        ctx.work.c.0 = ctx.master.c.0 ^ v.0
        ctx.work.c.1 = ctx.master.c.1 ^ v.1
        ctx.work.c.2 = ctx.master.c.2 ^ v.2
        ctx.work.c.3 = ctx.master.c.3 ^ v.3
        ctx.work.c.4 = ctx.master.c.4 ^ v.0
        ctx.work.c.5 = ctx.master.c.5 ^ v.1
        ctx.work.c.6 = ctx.master.c.6 ^ v.2
        ctx.work.c.7 = ctx.master.c.7 ^ v.3

        // copy rest of master to work (x, carry)
        ctx.work.x = ctx.master.x
        ctx.work.carry = ctx.master.carry

        // iterate system work ctx 4 times
        (0..<4).forEach {_ in
            nextState(master: false)
        }
        byteStream = []
    }

    func nextState(master master: Bool) {
        var p = master ? ctx.master: ctx.work
        let c = p.c

        p.c.0 = p.c.0 &+ 0x4D34D34D &+ p.carry
        p.c.1 = p.c.1 &+ 0xD34D34D3 &+ (p.c.0 < c.0 ? 1: 0)
        p.c.2 = p.c.2 &+ 0x34D34D34 &+ (p.c.1 < c.1 ? 1: 0)
        p.c.3 = p.c.3 &+ 0x4D34D34D &+ (p.c.2 < c.2 ? 1: 0)
        p.c.4 = p.c.4 &+ 0xD34D34D3 &+ (p.c.3 < c.3 ? 1: 0)
        p.c.5 = p.c.5 &+ 0x34D34D34 &+ (p.c.4 < c.4 ? 1: 0)
        p.c.6 = p.c.6 &+ 0x4D34D34D &+ (p.c.5 < c.5 ? 1: 0)
        p.c.7 = p.c.7 &+ 0xD34D34D3 &+ (p.c.6 < c.6 ? 1: 0)
        p.carry = p.c.7 < c.7 ? 1: 0

        // calculate g vector
        let g: Vect = (
            rabbitG(p.x.0 &+ p.c.0),
            rabbitG(p.x.1 &+ p.c.1),
            rabbitG(p.x.2 &+ p.c.2),
            rabbitG(p.x.3 &+ p.c.3),
            rabbitG(p.x.4 &+ p.c.4),
            rabbitG(p.x.5 &+ p.c.5),
            rabbitG(p.x.6 &+ p.c.6),
            rabbitG(p.x.7 &+ p.c.7)
        )

        // calculate new state values
        p.x.0 = g.0 &+ (g.7 << 16 | g.7 >> 16) &+ (g.6 << 16 | g.6 >> 16)
        p.x.1 = g.1 &+ (g.0 << 8 | g.0 >> 24) &+ g.7
        p.x.2 = g.2 &+ (g.1 << 16 | g.1 >> 16) &+ (g.0 << 16 | g.0 >> 16)
        p.x.3 = g.3 &+ (g.2 << 8 | g.2 >> 24) &+ g.1
        p.x.4 = g.4 &+ (g.3 << 16 | g.3 >> 16) &+ (g.2 << 16 | g.2 >> 16)
        p.x.5 = g.5 &+ (g.4 << 8 | g.4 >> 24) &+ g.3
        p.x.6 = g.6 &+ (g.5 << 16 | g.5 >> 16) &+ (g.4 << 16 | g.4 >> 16)
        p.x.7 = g.7 &+ (g.6 << 8 | g.6 >> 24) &+ g.5

        // update state
        if master {
            ctx.master = p
        } else {
            ctx.work = p
        }
    }

    func next()->UInt8 {
        if byteStream.isEmpty {
            nextState(master: false)
            var stream: Key = (
                (ctx.work.x.0 ^ ctx.work.x.5 >> 16 ^ ctx.work.x.3 << 16),
                (ctx.work.x.2 ^ ctx.work.x.7 >> 16 ^ ctx.work.x.5 << 16),
                (ctx.work.x.4 ^ ctx.work.x.1 >> 16 ^ ctx.work.x.7 << 16),
                (ctx.work.x.6 ^ ctx.work.x.3 >> 16 ^ ctx.work.x.1 << 16)
            )
            byteStream = withUnsafePointer(&stream) { (pt) -> [UInt8] in
                var arr: [UInt8] = []
                let pa = UnsafePointer<UInt8>(pt)
                for i in (0..<sizeof(Key)) {
                    arr.append((pa + i).memory)
                }
                return arr
            }
        }
        return byteStream.removeFirst()
    }
}

extension UTF8 {
    static func decode(arr: [UInt8])->String {
        var d = UTF8()
        var g = arr.generate()
        var str0 = ""
        loop: while true {
            switch d.decode(&g) {
            case .Result(let c): str0.append(c)
            case .Error:
                return "ERROR"
            case .EmptyInput:
                break loop
            }
        }
        return str0
    }
}

extension UnsignedIntegerType {
    var hex: String {
        var str = String(self, radix: 16, uppercase: true)
        while str.characters.count < 2 * sizeof(Self.self) {
            str.insert("0", atIndex: str.startIndex)
        }
        return str
    }
}

extension Array where Element: UnsignedIntegerType {
    var hex: String {
        var str = ""
        self.forEach { (u) in
            str.appendContentsOf(u.hex)
        }
        return str
    }
}

// helper functions for easy setup

func s2IV(str: String)->Rabbit.IV {
    return (
        UInt32(str.substringToIndex(str.startIndex.advancedBy(8)), radix: 16)!.bigEndian,
        UInt32(str.substringFromIndex(str.startIndex.advancedBy(8)), radix: 16)!.bigEndian)
}

func s2K(str: String)->Rabbit.Key {
    let s1 = str.startIndex.advancedBy(8)
    let s2 = str.startIndex.advancedBy(16)
    let s3 = str.startIndex.advancedBy(24)
    return (
        UInt32(str.substringToIndex(s1), radix: 16)!.bigEndian,
        UInt32(str.substringWithRange(s1..<s2), radix: 16)!.bigEndian,
        UInt32(str.substringWithRange(s2..<s3), radix: 16)!.bigEndian,
        UInt32(str.substringFromIndex(s3), radix: 16)!.bigEndian)
}

// helper functions for easy stream encryption / decryption

func cryptGenerator(key: Rabbit.Key? = nil, iv: Rabbit.IV? = nil, offset: Int64)->[UInt8]->[UInt8] {
    let r = Rabbit()
    if let k = key {
        r.keySetup(k)
    }
    if let v = iv {
        r.ivSetup(v)
    }
    // skip offset bytes from 'one time pad'
    let blockSize = Int64(sizeof(Rabbit.Key.self)) // for Rabbit, the block state size is 16 bytes
    var blockOffset = offset / blockSize
    while blockOffset > 0 {
        r.nextState(master: false)
        blockOffset -= 1
    }
    var byteOffset = offset % blockSize // remainding bytes to skip
    while byteOffset > 0 {
        r.next()
        byteOffset -= 1
    }
    // and return correct state for further encryption / decryption
    return { arr in
        return arr.map { $0 ^ r.next() }
    }
}

// helper class for file streaming
import Foundation

class FStream {
    let f:  UnsafeMutablePointer<FILE>
    init(path: String, mode: String) {
        f = fopen(path, mode)
    }
    deinit {
        fclose(f)
    }
    func write(data: [UInt8])->Bool { // returns false on error
        guard f != nil else { return false }
        var data = data
        return fwrite(&data, sizeof(UInt8.self), data.count, f) == data.count
    }
    func read(size: Int)->[UInt8]? { //return nil on error
        guard f != nil else { return nil }
        var data = [UInt8](count: size, repeatedValue: 0)
        let r = fread(&data, sizeof(UInt8.self), size, f)
        if r < size {
            if ferror(f) != 0 {
                return nil
            } else {
                return Array(data[0..<r])
            }
        }
        return data
    }
    func seek(offset: Int64)->Bool {
        guard f != nil else { return false }
        let s = fseeko(f, offset, SEEK_SET)
        if s < 0 {
            return false
        } else {
            return true
        }
    }
    func size()->Int64 {
        guard f != nil else { return -1 }
        let currPosition = ftello(f)
        let size = lseek(fileno(f), 0, SEEK_END)
        seek(currPosition)
        return size
    }
}
