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

#ifndef MLFILTER_H
#define MLFILTER_H

#include <vector>
#include <string>
#include <map>
#include <random>
#include <algorithm>
#include <cmath>

class MLFilter {
private:
    // Model parameters
    std::vector<double> weights;
    double bias;
    
    // Feature extraction parameters
    std::map<std::string, double> patternScores;
    std::map<char, double> charFrequencies;
    
    // Training data
    std::vector<std::vector<double>> trainingFeatures;
    std::vector<int> trainingLabels;
    
    // Random number generator
    std::mt19937 rng;
    
public:
    MLFilter();
    ~MLFilter();
    
    // Initialize the filter with default parameters
    void initialize();
    
    // Feature extraction methods
    std::vector<double> extractFeatures(const std::string& keyHex);
    double calculatePatternScore(const std::string& keyHex);
    double calculateFrequencyScore(const std::string& keyHex);
    double calculateEntropy(const std::string& keyHex);
    
    // Prediction methods
    double predict(const std::string& keyHex);
    bool isKeyFiltered(const std::string& keyHex);
    
    // Training methods
    void addTrainingSample(const std::string& keyHex, int label);
    void train();
    void updateWeights(const std::vector<double>& features, int label);
    
    // Utility methods
    void loadModel(const std::string& filename);
    void saveModel(const std::string& filename);
    void reset();
    
private:
    // Helper methods
    double sigmoid(double x);
    double dotProduct(const std::vector<double>& a, const std::vector<double>& b);
    void normalizeFeatures(std::vector<double>& features);
};

#endif // MLFILTER_H