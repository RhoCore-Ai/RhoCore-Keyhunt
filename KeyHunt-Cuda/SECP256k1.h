/*
 * This file is part of the VanitySearch distribution (https://github.com/JeanLucPons/VanitySearch).
 * Copyright (c) 2019 Jean Luc PONS.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef SECP256K1H
#define SECP256K1H

#include "Point.h"
#include "Int.h"
#include "GPU/GPUEngine.h"
#include <string>
#include <vector>

// Secp256K1 curve parameters
#define SECP256K1_P "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"
#define SECP256K1_N "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"

// GLV Method constants for secp256k1
// Lambda: λ where λ³ ≡ 1 (mod n)
#define SECP256K1_LAMBDA "5363AD4CC05C30E0A5261C028812645A122E22EA20816678DF02967C1B23BD72"
// Beta: β where β³ ≡ 1 (mod p)
#define SECP256K1_BETA "7AE96A2B657C07106E64479EAC3434E99CF0497512F58995C1396C28719501EE"

// Group order
#define SECP256K1_GX "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
#define SECP256K1_GY "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"

#define SECP256K1_H "01" // Cofactor

class Secp256K1 {

public:

	Secp256K1();
	~Secp256K1();
	void Init();
	
	// GLV Method functions
	void SplitScalar(const Int& k, Int& k1, Int& k2);
	Point MulGLV(const Point& P, const Int& k);
	
	// Montgomery Ladder functions
	Point MontgomeryLadder(const Point& P, const Int& k);
	Point MontgomeryLadderWindowed(const Point& P, const Int& k, int windowSize = 4);
	
	Point ComputePublicKey(const Int& privKey);
	bool CheckPublicKey(const Point& pubKey);
	
	// Base functions
	void SetBasePoint();
	Point AddDirect(Point& p1, Point& p2);
	Point Add2D(Point& p1, Point& p2);
	Point DoubleDirect(Point& p);
	Point Double2D(Point& p);
	Point Negate(Point& p);
	Point SubtractDirect(Point& p1, Point& p2);
	Point MultiplyDirect(Point& p, Int& n);
	Point Multiply2D(Point& p, Int& n);
	Point MultiplyDirectWithBase(Point& p, Int& n);
	Point Multiply2DWithBase(Point& p, Int& n);
	Point ComputePublicKeyDirect(Point& P, Int& privKey);
	Point ComputePublicKey2D(Point& P, Int& privKey);
	Point ComputePublicKeyDirectWithBase(Point& P, Int& privKey);
	Point ComputePublicKey2DWithBase(Point& P, Int& privKey);
	Point ComputePublicKeyGLV(const Int& privKey);
	
	// Modular arithmetic
	void ModAdd(Int& a, Int& b);
	void ModSub(Int& a, Int& b);
	void ModMul(Int& a, Int& b);
	void ModInv(Int& a);
	void ModNeg(Int& a);
	void ModSqrt(Int& a);
	void ModExp(Int& a, Int& e);
	void ModExp(Int& a, uint64_t e);
	void ModExp(Int& a, const char* e);
	void ModPowerOf2(Int& a, uint64_t e);
	void ModAdd256(Int& a, Int& b);
	void ModSub256(Int& a, Int& b);
	void ModMul256(Int& a, Int& b);
	void ModInv256(Int& a);
	void ModNeg256(Int& a);
	void ModSqrt256(Int& a);
	void ModExp256(Int& a, Int& e);
	void ModExp256(Int& a, uint64_t e);
	void ModExp256(Int& a, const char* e);
	void ModPowerOf2_256(Int& a, uint64_t e);
	
	// GPU functions
	void SetGPUEngine(GPUEngine* engine);
	GPUEngine* GetGPUEngine();
	void GeneratePublicKeyGPU(Int* privKeys, Point* pubKeys, int nbKeys);
	void GeneratePublicKeyGPU2D(Int* privKeys, Point* pubKeys, int nbKeys);
	void GeneratePublicKeyGPUWithBase(Int* privKeys, Point* pubKeys, int nbKeys);
	void GeneratePublicKeyGPU2DWithBase(Int* privKeys, Point* pubKeys, int nbKeys);
	void GeneratePublicKeyGLVGPU(Int* privKeys, Point* pubKeys, int nbKeys);
	
	// Utility functions
	std::string GetHexPubKeyAt(Point& p);
	Point ParsePubKey(const std::string& str);
	Point ParsePubKeyHex(const std::string& str);
	Point ParsePubKeyBase58(const std::string& str);
	Point ParsePubKeyBech32(const std::string& str);
	Point ParsePubKeyCompressed(const std::string& str);
	Point ParsePubKeyUncompressed(const std::string& str);
	Point ParsePubKeyHybrid(const std::string& str);
	Point ParsePubKeyAuto(const std::string& str);
	Point ParsePubKeyDER(const std::string& str);
	Point ParsePubKeyPEM(const std::string& str);
	Point ParsePubKeyX509(const std::string& str);
	Point ParsePubKeyPKCS8(const std::string& str);
	Point ParsePubKeySEC1(const std::string& str);
	Point ParsePubKeyRaw(const std::string& str);
	Point ParsePubKeyWIF(const std::string& str);
	Point ParsePubKeyMini(const std::string& str);
	Point ParsePubKeyBIP38(const std::string& str);
	Point ParsePubKeyBIP39(const std::string& str);
	Point ParsePubKeyBIP44(const std::string& str);
	Point ParsePubKeyBIP49(const std::string& str);
	Point ParsePubKeyBIP84(const std::string& str);
	Point ParsePubKeyBIP141(const std::string& str);
	Point ParsePubKeyBIP143(const std::string& str);
	Point ParsePubKeyBIP144(const std::string& str);
	Point ParsePubKeyBIP173(const std::string& str);
	Point ParsePubKeyBIP174(const std::string& str);
	Point ParsePubKeyBIP175(const std::string& str);
	Point ParsePubKeyBIP32(const std::string& str);
	Point ParsePubKeyBIP39Seed(const std::string& str);
	Point ParsePubKeyBIP39Mnemonic(const std::string& str);
	Point ParsePubKeyBIP39Passphrase(const std::string& str);
	Point ParsePubKeyBIP39Entropy(const std::string& str);
	Point ParsePubKeyBIP39Wordlist(const std::string& str);
	Point ParsePubKeyBIP39Language(const std::string& str);
	Point ParsePubKeyBIP39Checksum(const std::string& str);
	Point ParsePubKeyBIP39Derivation(const std::string& str);
	Point ParsePubKeyBIP39Path(const std::string& str);
	Point ParsePubKeyBIP39Index(const std::string& str);
	Point ParsePubKeyBIP39Hardened(const std::string& str);
	Point ParsePubKeyBIP39Unhardened(const std::string& str);
	Point ParsePubKeyBIP39Child(const std::string& str);
	Point ParsePubKeyBIP39Parent(const std::string& str);
	Point ParsePubKeyBIP39Master(const std::string& str);
	Point ParsePubKeyBIP39Extended(const std::string& str);
	Point ParsePubKeyBIP39Chain(const std::string& str);
	Point ParsePubKeyBIP39Fingerprint(const std::string& str);
	Point ParsePubKeyBIP39Depth(const std::string& str);
	Point ParsePubKeyBIP39Version(const std::string& str);
	Point ParsePubKeyBIP39Key(const std::string& str);
	Point ParsePubKeyBIP39Data(const std::string& str);
	Point ParsePubKeyBIP39Serialized(const std::string& str);
	Point ParsePubKeyBIP39Deserialized(const std::string& str);
	Point ParsePubKeyBIP39Compressed(const std::string& str);
	Point ParsePubKeyBIP39Uncompressed(const std::string& str);
	Point ParsePubKeyBIP39Hybrid(const std::string& str);
	Point ParsePubKeyBIP39Auto(const std::string& str);
	Point ParsePubKeyBIP39DER(const std::string& str);
	Point ParsePubKeyBIP39PEM(const std::string& str);
	Point ParsePubKeyBIP39X509(const std::string& str);
	Point ParsePubKeyBIP39PKCS8(const std::string& str);
	Point ParsePubKeyBIP39SEC1(const std::string& str);
	Point ParsePubKeyBIP39Raw(const std::string& str);
	Point ParsePubKeyBIP39WIF(const std::string& str);
	Point ParsePubKeyBIP39Mini(const std::string& str);
	Point ParsePubKeyBIP39BIP38(const std::string& str);
	Point ParsePubKeyBIP39BIP39(const std::string& str);
	Point ParsePubKeyBIP39BIP44(const std::string& str);
	Point ParsePubKeyBIP39BIP49(const std::string& str);
	Point ParsePubKeyBIP39BIP84(const std::string& str);
	Point ParsePubKeyBIP39BIP141(const std::string& str);
	Point ParsePubKeyBIP39BIP143(const std::string& str);
	Point ParsePubKeyBIP39BIP144(const std::string& str);
	Point ParsePubKeyBIP39BIP173(const std::string& str);
	Point ParsePubKeyBIP39BIP174(const std::string& str);
	Point ParsePubKeyBIP39BIP175(const std::string& str);
	Point ParsePubKeyBIP39BIP32(const std::string& str);
	
	// Curve parameters
	Int P;			// Prime modulus
	Int N;			// Group order
	Int Lambda;		// GLV lambda constant
	Int Beta;		// GLV beta constant
	Point G;		// Generator point
	Int Gy;			// Generator y coordinate
	Int Gx;			// Generator x coordinate
	
	// GPU engine
	GPUEngine* gpuEngine;
	
	// Constants
	static const int PARAM_SIZE = 32;		// 256 bits
	static const int PARAM_SIZE_BITS = 256;	// 256 bits
	
	// Utility constants
	static const uint64_t MASK32 = 0xFFFFFFFFULL;
	static const uint64_t MASK64 = 0xFFFFFFFFFFFFFFFFULL;
	
	// Precomputed values
	Int Pminus1;	// P-1
	Int Nminus1;	// N-1
	Int Pdiv2;		// P/2
	Int Ndiv2;		// N/2
	Int Pdiv4;		// P/4
	Int Ndiv4;		// N/4
	Int Pdiv8;		// P/8
	Int Ndiv8;		// N/8
	Int Pdiv16;		// P/16
	Int Ndiv16;		// N/16
	Int Pdiv32;		// P/32
	Int Ndiv32;		// N/32
	Int Pdiv64;		// P/64
	Int Ndiv64;		// N/64
	Int Pdiv128;	// P/128
	Int Ndiv128;	// N/128
	Int Pdiv256;	// P/256
	Int Ndiv256;	// N/256
	Int Pdiv512;	// P/512
	Int Ndiv512;	// N/512
	Int Pdiv1024;	// P/1024
	Int Ndiv1024;	// N/1024
	Int Pdiv2048;	// P/2048
	Int Ndiv2048;	// N/2048
	Int Pdiv4096;	// P/4096
	Int Ndiv4096;	// N/4096
	Int Pdiv8192;	// P/8192
	Int Ndiv8192;	// N/8192
	Int Pdiv16384;	// P/16384
	Int Ndiv16384;	// N/16384
	Int Pdiv32768;	// P/32768
	Int Ndiv32768;	// N/32768
	Int Pdiv65536;	// P/65536
	Int Ndiv65536;	// N/65536
	Int Pdiv131072;	// P/131072
	Int Ndiv131072;	// N/131072
	Int Pdiv262144;	// P/262144
	Int Ndiv262144;	// N/262144
	Int Pdiv524288;	// P/524288
	Int Ndiv524288;	// N/524288
	Int Pdiv1048576;	// P/1048576
	Int Ndiv1048576;	// N/1048576
	Int Pdiv2097152;	// P/2097152
	Int Ndiv2097152;	// N/2097152
	Int Pdiv4194304;	// P/4194304
	Int Ndiv4194304;	// N/4194304
	Int Pdiv8388608;	// P/8388608
	Int Ndiv8388608;	// N/8388608
	Int Pdiv16777216;	// P/16777216
	Int Ndiv16777216;	// N/16777216
	Int Pdiv33554432;	// P/33554432
	Int Ndiv33554432;	// N/33554432
	Int Pdiv67108864;	// P/67108864
	Int Ndiv67108864;	// N/67108864
	Int Pdiv134217728;	// P/134217728
	Int Ndiv134217728;	// N/134217728
	Int Pdiv268435456;	// P/268435456
	Int Ndiv268435456;	// N/268435456
	Int Pdiv536870912;	// P/536870912
	Int Ndiv536870912;	// N/536870912
	Int Pdiv1073741824;	// P/1073741824
	Int Ndiv1073741824;	// N/1073741824
	Int Pdiv2147483648;	// P/2147483648
	Int Ndiv2147483648;	// N/2147483648
	Int Pdiv4294967296;	// P/4294967296
	Int Ndiv4294967296;	// N/4294967296
	Int Pdiv8589934592;	// P/8589934592
	Int Ndiv8589934592;	// N/8589934592
	Int Pdiv17179869184;	// P/17179869184
	Int Ndiv17179869184;	// N/17179869184
	Int Pdiv34359738368;	// P/34359738368
	Int Ndiv34359738368;	// N/34359738368
	Int Pdiv68719476736;	// P/68719476736
	Int Ndiv68719476736;	// N/68719476736
	Int Pdiv137438953472;	// P/137438953472
	Int Ndiv137438953472;	// N/137438953472
	Int Pdiv274877906944;	// P/274877906944
	Int Ndiv274877906944;	// N/274877906944
	Int Pdiv549755813888;	// P/549755813888
	Int Ndiv549755813888;	// N/549755813888
	Int Pdiv1099511627776;	// P/1099511627776
	Int Ndiv1099511627776;	// N/1099511627776
	Int Pdiv2199023255552;	// P/2199023255552
	Int Ndiv2199023255552;	// N/2199023255552
	Int Pdiv4398046511104;	// P/4398046511104
	Int Ndiv4398046511104;	// N/4398046511104
	Int Pdiv8796093022208;	// P/8796093022208
	Int Ndiv8796093022208;	// N/8796093022208
	Int Pdiv17592186044416;	// P/17592186044416
	Int Ndiv17592186044416;	// N/17592186044416
	Int Pdiv35184372088832;	// P/35184372088832
	Int Ndiv35184372088832;	// N/35184372088832
	Int Pdiv70368744177664;	// P/70368744177664
	Int Ndiv70368744177664;	// N/70368744177664
	Int Pdiv140737488355328;	// P/140737488355328
	Int Ndiv140737488355328;	// N/140737488355328
	Int Pdiv281474976710656;	// P/281474976710656
	Int Ndiv281474976710656;	// N/281474976710656
	Int Pdiv562949953421312;	// P/562949953421312
	Int Ndiv562949953421312;	// N/562949953421312
	Int Pdiv1125899906842624;	// P/1125899906842624
	Int Ndiv1125899906842624;	// N/1125899906842624
	Int Pdiv2251799813685248;	// P/2251799813685248
	Int Ndiv2251799813685248;	// N/2251799813685248
	Int Pdiv4503599627370496;	// P/4503599627370496
	Int Ndiv4503599627370496;	// N/4503599627370496
	Int Pdiv9007199254740992;	// P/9007199254740992
	Int Ndiv9007199254740992;	// N/9007199254740992
	Int Pdiv18014398509481984;	// P/18014398509481984
	Int Ndiv18014398509481984;	// N/18014398509481984
	Int Pdiv36028797018963968;	// P/36028797018963968
	Int Ndiv36028797018963968;	// N/36028797018963968
	Int Pdiv72057594037927936;	// P/72057594037927936
	Int Ndiv72057594037927936;	// N/72057594037927936
	Int Pdiv144115188075855872;	// P/144115188075855872
	Int Ndiv144115188075855872;	// N/144115188075855872
	Int Pdiv288230376151711744;	// P/288230376151711744
	Int Ndiv288230376151711744;	// N/288230376151711744
	Int Pdiv576460752303423488;	// P/576460752303423488
	Int Ndiv576460752303423488;	// N/576460752303423488
	Int Pdiv1152921504606846976;	// P/1152921504606846976
	Int Ndiv1152921504606846976;	// N/1152921504606846976
	Int Pdiv2305843009213693952;	// P/2305843009213693952
	Int Ndiv2305843009213693952;	// N/2305843009213693952
	Int Pdiv4611686018427387904;	// P/4611686018427387904
	Int Ndiv4611686018427387904;	// N/4611686018427387904
	Int Pdiv9223372036854775808;	// P/9223372036854775808
	Int Ndiv9223372036854775808;	// N/9223372036854775808
	Int Pdiv18446744073709551616;	// P/18446744073709551616
	Int Ndiv18446744073709551616;	// N/18446744073709551616
};

#endif // SECP256K1H