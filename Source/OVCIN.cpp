// OVCIN.cpp

#include "OVCIN.h"
#include "OVFileHandler.h"
#include "OVStringToolKit.h"

#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <cctype>
#include <algorithm>

using namespace std;

/*
OVEncoding OVEncodingMapper(const char *s)
{
    if (!strcasecmp(s, "big5")) return ovEncodingBig5HKSCS;
    if (!strcasecmp(s, "big5e")) return ovEncodingBig5HKSCS;
    if (!strcasecmp(s, "big5hkscs")) return ovEncodingBig5HKSCS;
    if (!strcasecmp(s, "big5-hkscs")) return ovEncodingBig5HKSCS;
    if (!strcasecmp(s, "euc")) return ovEncodingEUC_CN;
    if (!strcasecmp(s, "euc_cn")) return ovEncodingEUC_CN;
    return ovEncodingUTF8;
}
*/

OVCIN::OVCIN(char* fileName)
{
	OVFileHandler* fileHandler = new OVFileHandler(fileName);
	vector<string> stringVector;
	fileHandler->getLines(stringVector);
	delete fileHandler;
	
	ename = getPropertyByName(stringVector, "ename");
	cname = getPropertyByName(stringVector, "cname");
	selkey = getPropertyByName(stringVector, "selkey");
	encoding = getPropertyByName(stringVector, "encoding");	
	endkey = getPropertyByName(stringVector, "endkey");
	
	getMapByName(stringVector, keyMap, "keyname");
	getMapByName(stringVector, charMap, "chardef");
}

OVCIN::~OVCIN()
{
	charMap.clear();
	keyMap.clear();
}

string& OVCIN::getSelKey()
{
	return selkey;
}

string& OVCIN::getCName()
{
	return cname;
}

string& OVCIN::getEName()
{
	return ename;
}

string& OVCIN::getEncoding()
{
	return encoding;
}

string& OVCIN::getEndKey()
{
	return endkey;
}

bool OVCIN::isEndKey(char keyChar)
{
	int foundIndex = endkey.find(keyChar, 0);
	if(foundIndex > -1)
		return true;
	else
		return false;
}

bool OVCIN::isValidKey(string keyString)
{
	if(keyMap.count(keyString) > 0)
		return true;
	else
		return false;
}

int OVCIN::getCharVectorByKey(string inKey,
							  vector<string>& outStringVectorRef)
{
	return getVectorFromMap(keyMap, inKey, outStringVectorRef);
}

int OVCIN::getWordVectorByChar(string inKey,
							   vector<string>& outStringVectorRef)
{
	return getVectorFromMap(charMap, inKey, outStringVectorRef);
}

int OVCIN::getVectorFromMap(map< string, vector<string> >& inMapRef,
							string inKey,
							vector<string>& outStringVectorRef)
{
	outStringVectorRef = inMapRef[inKey];
	
	return inMapRef[inKey].size();
}
 
string OVCIN::getPropertyByName(vector<string>& inStringVectorRef,
								 string propertyName)
{
	string pattern = "%" + propertyName;
	vector<string> delimiters;
	delimiters.push_back(" ");
	delimiters.push_back("\t");
	for(unsigned int i = 0; i < inStringVectorRef.size(); i++)
	{
		string currentString = inStringVectorRef[i];
		if(currentString.find(pattern, 0) == 0) {
			vector<string> tempVectorRef;
			OVStringToolKit::splitString(currentString, tempVectorRef,
										 delimiters, false); 
			return tempVectorRef[1];
		}
	}
	
	return string("");
}

int OVCIN::getMapByName(vector<string>& inStringVectorRef,
						 map< string, vector<string> >& outMapRef,
						 string mapName)
{
	bool doGet = false;
	string sectionMark = "begin";
	vector<string> delimiters;
	delimiters.push_back(" ");
	delimiters.push_back("\t");
	for(unsigned int i = 0; i < inStringVectorRef.size(); i++)
	{
		string currentString = inStringVectorRef[i];
		int foundIndex = currentString.find("%" + mapName, 0);
		int foundComment = currentString.find("#", 0);
		if(!doGet) {
			if(foundIndex == 0) {
				int foundBegin = currentString.find(sectionMark, foundIndex);
				if(foundBegin > -1) {	// ready to read name-value pairs
					doGet = true;
					sectionMark = "end";
				}
			}
		} else {
			if(foundIndex == 0) {
				int foundEnd = currentString.find(sectionMark, foundIndex);
				if(foundEnd > -1)	// stop reading pairs
					break;
			} else if(foundComment != 0) {
				vector<string> pairVector;
				if(foundComment > 0)
					currentString = currentString.substr(0, foundComment);
				int vectorSize =
					OVStringToolKit::splitString(currentString, pairVector,
												 delimiters, false);
				if(vectorSize == 2) {
					string keyString = pairVector[0];
					string valueString = pairVector[1];
					transform(keyString.begin(), keyString.end(),
							  keyString.begin(), (int(*)(int))tolower);
					if(outMapRef.find(keyString) == outMapRef.end()) {
						vector<string> currentVector;
						currentVector.push_back(valueString);
						outMapRef.insert(make_pair(keyString,
												   currentVector));
					} else
						outMapRef[keyString].push_back(valueString);
				}
			}
		} // The end of if(!doGet)
	} // The end of for
	
	return outMapRef.size();
}