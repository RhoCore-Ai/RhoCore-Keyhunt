/*
 * This file is part of the KeyHunt distribution (https://github.com/robert-zaremba/keyhunt).
 * Copyright (c) 2024 Robert Zaremba.
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

#include "MLFilter.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <cmath>
#include <numeric>

MLFilter::MLFilter() : rng(std::random_device{}()) {
    initialize();
}

MLFilter::~MLFilter() {
    // Cleanup if needed
}

void MLFilter::initialize() {
    // Initialize weights with small random values
    weights = std::vector<double>(4, 0.0); // 4 features
    bias = 0.0;
    
    // Initialize pattern scores for common patterns
    patternScores["000"] = -0.8;  // Strong negative score for triple zeros
    patternScores["111"] = -0.7;
    patternScores["222"] = -0.7;
    patternScores["333"] = -0.7;
    patternScores["444"] = -0.7;
    patternScores["555"] = -0.7;
    patternScores["666"] = -0.7;
    patternScores["777"] = -0.7;
    patternScores["888"] = -0.7;
    patternScores["999"] = -0.7;
    patternScores["aaa"] = -0.7;
    patternScores["bbb"] = -0.7;
    patternScores["ccc"] = -0.7;
    patternScores["ddd"] = -0.7;
    patternScores["eee"] = -0.7;
    patternScores["fff"] = -0.7;
    
    // Initialize character frequencies (based on typical key distributions)
    charFrequencies['0'] = 0.1;
    charFrequencies['1'] = 0.1;
    charFrequencies['2'] = 0.1;
    charFrequencies['3'] = 0.1;
    charFrequencies['4'] = 0.1;
    charFrequencies['5'] = 0.1;
    charFrequencies['6'] = 0.1;
    charFrequencies['7'] = 0.1;
    charFrequencies['8'] = 0.1;
    charFrequencies['9'] = 0.1;
    charFrequencies['a'] = 0.1;
    charFrequencies['b'] = 0.1;
    charFrequencies['c'] = 0.1;
    charFrequencies['d'] = 0.1;
    charFrequencies['e'] = 0.1;
    charFrequencies['f'] = 0.1;
}

std::vector<double> MLFilter::extractFeatures(const std::string& keyHex) {
    std::vector<double> features(4);
    
    // Feature 1: Pattern score
    features[0] = calculatePatternScore(keyHex);
    
    // Feature 2: Frequency score
    features[1] = calculateFrequencyScore(keyHex);
    
    // Feature 3: Entropy
    features[2] = calculateEntropy(keyHex);
    
    // Feature 4: Length normalized score
    features[3] = static_cast<double>(keyHex.length()) / 64.0; // Normalize to 0-1 range
    
    // Normalize features
    normalizeFeatures(features);
    
    return features;
}

double MLFilter::calculatePatternScore(const std::string& keyHex) {
    double score = 0.0;
    
    // Check for repeated patterns
    for (size_t i = 0; i < keyHex.length() && i + 2 < keyHex.length(); ++i) {
        std::string pattern = keyHex.substr(i, 3);
        if (patternScores.find(pattern) != patternScores.end()) {
            score += patternScores[pattern];
        }
    }
    
    // Check for sequential patterns
    for (size_t i = 0; i < keyHex.length() && i + 2 < keyHex.length(); ++i) {
        char c1 = keyHex[i];
        char c2 = keyHex[i+1];
        char c3 = keyHex[i+2];
        
        // Check for ascending sequence
        if (c2 == c1 + 1 && c3 == c2 + 1) {
            score -= 0.3;
        }
        
        // Check for descending sequence
        if (c2 == c1 - 1 && c3 == c2 - 1) {
            score -= 0.3;
        }
    }
    
    return score;
}

double MLFilter::calculateFrequencyScore(const std::string& keyHex) {
    double score = 0.0;
    std::map<char, int> charCount;
    
    // Count character frequencies
    for (char c : keyHex) {
        charCount[c]++;
    }
    
    // Calculate chi-square like score
    double expectedFreq = static_cast<double>(keyHex.length()) / 16.0; // Expected frequency for uniform distribution
    for (const auto& pair : charCount) {
        double diff = pair.second - expectedFreq;
        score -= (diff * diff) / expectedFreq; // Negative because higher difference is worse
    }
    
    return score / keyHex.length(); // Normalize by key length
}

double MLFilter::calculateEntropy(const std::string& keyHex) {
    std::map<char, int> charCount;
    
    // Count character frequencies
    for (char c : keyHex) {
        charCount[c]++;
    }
    
    // Calculate entropy
    double entropy = 0.0;
    double keyLength = static_cast<double>(keyHex.length());
    
    for (const auto& pair : charCount) {
        double probability = pair.second / keyLength;
        if (probability > 0) {
            entropy -= probability * log2(probability);
        }
    }
    
    // Normalize to 0-1 range (max entropy for 16 symbols is log2(16) = 4)
    return entropy / 4.0;
}

double MLFilter::predict(const std::string& keyHex) {
    std::vector<double> features = extractFeatures(keyHex);
    double score = dotProduct(features, weights) + bias;
    return sigmoid(score);
}

bool MLFilter::isKeyFiltered(const std::string& keyHex) {
    double probability = predict(keyHex);
    // Filter keys with probability > 0.7 of being "bad"
    return probability > 0.7;
}

void MLFilter::addTrainingSample(const std::string& keyHex, int label) {
    std::vector<double> features = extractFeatures(keyHex);
    trainingFeatures.push_back(features);
    trainingLabels.push_back(label);
}

void MLFilter::train() {
    // Simple perceptron training
    const double learningRate = 0.01;
    const int maxIterations = 1000;
    
    for (int iter = 0; iter < maxIterations; ++iter) {
        bool converged = true;
        
        for (size_t i = 0; i < trainingFeatures.size(); ++i) {
            std::vector<double> features = trainingFeatures[i];
            int label = trainingLabels[i];
            
            double prediction = predict(features); // This won't work directly, need to reimplement
            // Let's reimplement a simpler training approach
            
            double score = dotProduct(features, weights) + bias;
            double prediction = sigmoid(score);
            
            int target = label > 0 ? 1 : 0;
            double error = target - prediction;
            
            if (std::abs(error) > 0.001) { // If error is significant
                converged = false;
                // Update weights
                for (size_t j = 0; j < weights.size(); ++j) {
                    weights[j] += learningRate * error * features[j];
                }
                bias += learningRate * error;
            }
        }
        
        if (converged) break;
    }
}

void MLFilter::updateWeights(const std::vector<double>& features, int label) {
    // Online learning update
    const double learningRate = 0.01;
    
    double score = dotProduct(features, weights) + bias;
    double prediction = sigmoid(score);
    
    int target = label > 0 ? 1 : 0;
    double error = target - prediction;
    
    // Update weights
    for (size_t j = 0; j < weights.size(); ++j) {
        weights[j] += learningRate * error * features[j];
    }
    bias += learningRate * error;
}

void MLFilter::loadModel(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Could not open model file: " << filename << std::endl;
        return;
    }
    
    std::string line;
    // Read weights
    if (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string value;
        weights.clear();
        while (std::getline(ss, value, ',')) {
            weights.push_back(std::stod(value));
        }
    }
    
    // Read bias
    if (std::getline(file, line)) {
        bias = std::stod(line);
    }
    
    file.close();
}

void MLFilter::saveModel(const std::string& filename) {
    std::ofstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Could not open model file: " << filename << std::endl;
        return;
    }
    
    // Write weights
    for (size_t i = 0; i < weights.size(); ++i) {
        if (i > 0) file << ",";
        file << weights[i];
    }
    file << std::endl;
    
    // Write bias
    file << bias << std::endl;
    
    file.close();
}

void MLFilter::reset() {
    weights = std::vector<double>(4, 0.0);
    bias = 0.0;
    trainingFeatures.clear();
    trainingLabels.clear();
}

double MLFilter::sigmoid(double x) {
    return 1.0 / (1.0 + std::exp(-x));
}

double MLFilter::dotProduct(const std::vector<double>& a, const std::vector<double>& b) {
    double result = 0.0;
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) {
        result += a[i] * b[i];
    }
    return result;
}

void MLFilter::normalizeFeatures(std::vector<double>& features) {
    // Simple min-max normalization to [0,1] range
    // In practice, you might want to use z-score normalization with precomputed means and std devs
    
    // For now, we'll assume features are already in a reasonable range
    // and just clamp them to prevent extreme values
    for (double& feature : features) {
        if (feature > 10.0) feature = 10.0;
        if (feature < -10.0) feature = -10.0;
    }
}