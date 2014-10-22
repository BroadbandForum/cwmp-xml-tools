// from http://stackoverflow.com/questions/17389487/c-how-to-replace-unusual-quotes-in-code

#include <iostream>
#include <fstream>
#include <string>

using namespace std;

// Function Declaration
bool replace(string& str, const string& from, const string& to);

bool checkMyLine(string line);

// Main
int main(int argc, char *argv[]) {

    // line to edit
    string line;

    fstream stri;
    // ifstream in
    stri.open(argv[1], ios::in);
    if(stri.fail()){
        cerr << "File failed to open for input" << endl;
        return 1;
    }

    // Read - Write
    while(getline(stri, line, '\n')){

    // Remove numbers at start of each line followed by space, eg: "001: "
#if 0
    int i;
    for(i = 0;i < line.length();i++)
    {
        if(line[i] == ' ') break;
    }
    line.erase(0,i+1);
#endif

        //Replace Odd Chars
        for(int i=0;i<line.length();i++)
        {

	// these are Unicode characters
#if 0
        replace(line, "\u2018","\'");   // replaces ‘
        replace(line, "\u2019","\'");   // replaces ’
        replace(line, "\u201C","\"");   // replaces “
        replace(line, "\u201D","\"");   // replaces ”
#endif

	// these are ISO 8859-1 characters
        replace(line, "\x91","\'");     // replaces ‘
        replace(line, "\x92","\'");     // replaces ’
        replace(line, "\x93","\"");     // replaces “
        replace(line, "\x94","\"");     // replaces ”
        }

        // Write to file
        cout << line << endl;
    }

    // Close files
    stri.close();
}

bool replace(string& str, const string& from, const string& to) 
{
    size_t start_pos = str.find(from);
    if(start_pos == string::npos)
        return false;
    str.replace(start_pos, from.length(), to);
    return true;
}
