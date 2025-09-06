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
#include <string>
#include <vector>
#include <cstdint>

class Secp256K1
{

public:

	Secp256K1();
	~Secp256K1();

	void Init();
	Point ComputePublicKey(Int& privKey);
	Point NextKey(Point& key);
	std::string GetPublicKeyHex(bool compressed, Point& pubKey);
	std::string GetAddress(bool compressed, Point& pubKey);
	std::string GetAddressETH(Point& pubKey);
	void GetHash160(bool compressed, Point& pubKey, uint8_t* hash);
	void GetHash160ETH(Point& pubKey, uint8_t* hash);
	bool CheckPublicKey(Point& pubKey);
	Point Add(Point& p1, Point& p2);
	Point Double(Point& p);
	Point ScalarMultiplication(Point& p, Int& scalar);
	void GetRandomKey(Int& privKey, Point& pubKey);
	void GetRandomKey(Int& privKey);
	void GetRandomKey(Point& pubKey);
	void GetRandomKey(std::vector<unsigned char>& privKey, std::vector<unsigned char>& pubKey);
	void GetRandomKey(std::vector<unsigned char>& privKey);
	void GetRandomKey(std::vector<unsigned char>& pubKey);
	void GetRandomKey(unsigned char* privKey, unsigned char* pubKey);
	void GetRandomKey(unsigned char* privKey);
	void GetRandomKey(unsigned char* pubKey);
	void GetRandomKey(std::string& privKey, std::string& pubKey);
	void GetRandomKey(std::string& privKey);
	void GetRandomKey(std::string& pubKey);
	void GetRandomKey(Int& privKey, std::string& pubKey);
	void GetRandomKey(std::string& privKey, Point& pubKey);
	void GetRandomKey(Point& pubKey, std::string& addr);
	void GetRandomKey(std::string& privKey, std::string& pubKey, std::string& addr);
	void GetRandomKey(Int& privKey, Point& pubKey, std::string& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, Point& pubKey, std::string& addr);
	void GetRandomKey(unsigned char* privKey, Point& pubKey, std::string& addr);
	void GetRandomKey(std::string& privKey, Point& pubKey, std::string& addr);
	void GetRandomKey(Int& privKey, std::vector<unsigned char>& pubKey, std::string& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, std::vector<unsigned char>& pubKey, std::string& addr);
	void GetRandomKey(unsigned char* privKey, std::vector<unsigned char>& pubKey, std::string& addr);
	void GetRandomKey(std::string& privKey, std::vector<unsigned char>& pubKey, std::string& addr);
	void GetRandomKey(Int& privKey, unsigned char* pubKey, std::string& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, unsigned char* pubKey, std::string& addr);
	void GetRandomKey(unsigned char* privKey, unsigned char* pubKey, std::string& addr);
	void GetRandomKey(std::string& privKey, unsigned char* pubKey, std::string& addr);
	void GetRandomKey(Int& privKey, Point& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, Point& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(unsigned char* privKey, Point& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::string& privKey, Point& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(Int& privKey, std::vector<unsigned char>& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, std::vector<unsigned char>& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(unsigned char* privKey, std::vector<unsigned char>& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::string& privKey, std::vector<unsigned char>& pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(Int& privKey, unsigned char* pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, unsigned char* pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(unsigned char* privKey, unsigned char* pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(std::string& privKey, unsigned char* pubKey, std::vector<unsigned char>& addr);
	void GetRandomKey(Int& privKey, Point& pubKey, unsigned char* addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, Point& pubKey, unsigned char* addr);
	void GetRandomKey(unsigned char* privKey, Point& pubKey, unsigned char* addr);
	void GetRandomKey(std::string& privKey, Point& pubKey, unsigned char* addr);
	void GetRandomKey(Int& privKey, std::vector<unsigned char>& pubKey, unsigned char* addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, std::vector<unsigned char>& pubKey, unsigned char* addr);
	void GetRandomKey(unsigned char* privKey, std::vector<unsigned char>& pubKey, unsigned char* addr);
	void GetRandomKey(std::string& privKey, std::vector<unsigned char>& pubKey, unsigned char* addr);
	void GetRandomKey(Int& privKey, unsigned char* pubKey, unsigned char* addr);
	void GetRandomKey(std::vector<unsigned char>& privKey, unsigned char* pubKey, unsigned char* addr);
	void GetRandomKey(unsigned char* privKey, unsigned char* pubKey, unsigned char* addr);
	void GetRandomKey(std::string& privKey, unsigned char* pubKey, unsigned char* addr);

private:

	Point G;
	Int order;

};