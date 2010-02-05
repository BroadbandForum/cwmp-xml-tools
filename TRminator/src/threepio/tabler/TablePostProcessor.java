/*
 * File: TablePostProcessor.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package threepio.tabler;

import java.io.File;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map.Entry;
import threepio.engine.ExclusiveArrayList;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.Row;
import threepio.tabler.container.StringCell;
import threepio.tabler.container.Table;
import threepio.tabler.container.XTable;

/**
 * The TablePostProcessor performs operations on Tables that are best left until
 * The table has been completely constructed.
 * @author jhoule
 */
public class TablePostProcessor
{

    private final String patternListName = "patterns", hasPatterns = "patternsDefined";
    private final String[] allowed =
    {
        "bibref", "section", "param", "object",
        "list", "nolist", "reference", "noreference", "enum", "noenum", "pattern", "nopattern",
        "hidden", "nohidden", "keys", "nokeys", "units", "false", "true", "empty", "null"
    };

    /**
     * makes and returns a hashmap with keys of row names and values of the value in leftmost column of the row.
     * essentially, aStatement returns the table chopped down to the leftmost column.
     * @param t - the table
     * @return the map of the row names and values in 0th column.
     */
    private HashMap<String, String> tableToNameHash(XTable t)
    {
        HashMap<String, String> map;

        Entry<String, Row> temp;
        String name;
        int l;

        if (t == null)
        {
            return null;
        }

        map = new HashMap<String, String>();

        for (int i = 0; i < t.size(); i++)
        {
            temp = t.get(i);
            name = temp.getValue().get(0).getData();

            if (!temp.getKey().equalsIgnoreCase("HEADER"))
            {
                l = name.indexOf("<a");
                if (l >= 0)
                {
                    l = name.indexOf("a>", l) + 2;
                    name = name.substring(l);
                }
            }

            map.put(temp.getKey(), name);
        }

        return map;
    }

    /**
     * firstPass goes through and marks stuff needed for the processors.
     * @param table - the table to modify
     * @return the table that has been modified.
     */
    private ModelTable firstPass(ModelTable table, int toAnchor)
    {
        String data, temp, rowName;
        Row r;
        StringBuffer buff;
        ExclusiveArrayList<String> patterns;
        int start, end;
        String[] parts;
        int firstRow;

        // skip over the header row, if existent.
        if (table.size() > 1 && table.get(0).getKey().equalsIgnoreCase("HEADER"))
        {
            firstRow = 1;
        } else
        {
            firstRow = 0;
        }


        for (int i = firstRow; i < table.size(); i++)
        {
            r = table.get(i).getValue();
            rowName = table.get(i).getKey();

            for (int j = 0; j < r.size(); j++)
            {
                data = r.get(j).getData();

                if (j == toAnchor)
                {
                    data = "<a name=\"" + rowName.replace(".", "_") + "\">" + data + "</a>";

                    r.get(j).silentSet(data);
                }


                if (data.contains("{{pattern") && !data.contains("{{nopattern"))
                {

                    // PASS 1: collecting patterns

                    patterns = new ExclusiveArrayList<String>();
                    patterns.setName(patternListName);
                    buff = new StringBuffer();
                    buff.append(data);

                    end = 0;
                    start = buff.indexOf("{{pattern");
                    while (start >= 0)
                    {
                        end = buff.indexOf("}}", start) + 2;
                        temp = buff.substring(start, end);

                        parts = temp.split("\\|");

                        parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                        if (parts.length == 2)
                        {
                            r.getParams().put(hasPatterns, "true");

                            patterns.add(parts[1].trim());
                        }


                        start = buff.indexOf("{{pattern", end);
                    }
                    r.getBucket().add(patterns);
                    r.silentSet(j, buff.toString());
                }

            }
        }
        return table;
    }

    /**
     * deMarkupTable processes the data of every cell in a table, replacing definitions in curly braces
     * with the appropriate string(s).
     * This should be used before printing a table as a post-MarkupProcessor, to scrub the table of defintions.
     * @param table - a Table that has already been made.
     * @param fileErr - a File to output errors to.
     * @param colType - the index of the rows that will contain types.
     * @return The table that has been processed.
     * @throws Exception - when unclosed markup is found.
     */
    public ModelTable deMarkupTable(ModelTable table, File fileErr, int colType) throws Exception
    {
        Row row = null;
        String data = null, rowName;
        String[] statements;
        int bar, rbrack, terminator, firstRow;

        ExclusiveArrayList<String> errors = new ExclusiveArrayList<String>();
        String aStatement;

        System.out.println("running post-processor on table");

        // compose map for coded document names and actual document names.
        HashMap<String, String> referenceNames = tableToNameHash(table.getBiblio());

        // make an array of instantiated of the DataProcessors to be used.
        MarkupProcessor[] procs =
        {
            new BoolProcessor(),
            new BibrefProcessor(),
            new MiscProcessor(),
            new EnumProcessor(),
            new HiddenProcessor(),
            new KeyProcessor(),
            new ListProcessor(),
            new PaoProcessor(),
            new PatternProcessor(),
            new ReferenceProcessor(),
            new SectionProcessor(),
            new UnitsProcessor()
        };

        firstPass(table, 0);

        // skip over the header row, if existent.
        if (table.size() > 1 && table.get(0).getKey().equalsIgnoreCase("HEADER"))
        {
            firstRow = 1;
        } else
        {
            firstRow = 0;
        }

        // loop through rows (i is row index)
        for (int i = firstRow; i < table.size(); i++)
        {
            rowName = table.get(i).getKey();
            row = table.get(i).getValue();

            // loop through cells (j is cell index)
            for (int j = 0; j < row.size(); j++)
            {
                // yank data from cell
                data = row.get(j).getData();

                if (data != null)
                {
                    // get the raw markup
                    statements = data.split("\\{\\{");

                    // validate markup (k is statement index)
                    for (int k = 1; k < statements.length; k++)
                    {
                        aStatement = statements[k];
                        bar = aStatement.indexOf("|");
                        rbrack = aStatement.indexOf('}');

                        if (bar >= 0 && (rbrack < 0 || bar <= rbrack))
                        {
                            terminator = bar;
                        } else
                        {
                            terminator = rbrack;
                        }

                        if (terminator < 0)
                        {
                            throw new Exception("could not find end of markup");
                        }

                        // cut the markup down to the first word
                        aStatement = aStatement.substring(0, terminator);

                        // check against list of known markup statements
                        if (!statementIsAllowed(aStatement))
                        {
                            // there is unknown markup. list where aStatement happens.
                            errors.add(rowName + ": unknown markup: " + aStatement);
                        }
                    }


                    // put the string through each processor (m is processor index).
                    for (int m = 0; m < procs.length; m++)
                    {

                        procs[m].reset();
                        procs[m].deMarkup(data, table, rowName, row, colType, referenceNames);
                        data = procs[m].getResult();


                        errors.add(procs[m].getErrs());
                    }

                    // set the cell data to processed data.
                    row.silentSet(j, data);
                }
            }
        }

        // print out the file buffer after all cells worked on.
        printString(errors.toString(), fileErr);

        System.out.println("post-processor ran successfully");
        if (errors.size() > 0)
        {
            System.out.println("There are " + errors.size() + " warnings in " + fileErr.getName());
        }

        return table;
    }

    @SuppressWarnings("empty-statement")
    private boolean statementIsAllowed(String s)
    {
        int i;
        for (i = 0; ((i < allowed.length) && !(allowed[i].equals(s))); i++);

        return (i < allowed.length);

    }

    /**
     * printString attempts to print a passed string to a passed file.
     * @param str - the string
     * @param out - the file
     * @throws Exception - when the file cannot be written or is null.
     */
    private void printString(String str, File out) throws Exception
    {
        FileWriter writer;

       

        if (out.exists())
        {
            out.delete();
        }

        out.createNewFile();

        if (!out.canWrite())
        {
            throw new Exception("cannot output to file: " + out.getPath());
        }

        writer = new FileWriter(out);

        writer.write(str);
        writer.close();
    }

    /**
     * anchorIt places anchor tags (HTML) in the cells at index
     * so that a link to # + text in that cell will scroll to it.
     * @param t - the table to place the anchors in.
     * @param index - the index in the rows to anchor.
     */
    public void anchorIt(ModelTable t, int index)
    {
        Entry<String, Row> ent;
        StringCell cell;
        String data;

        for (int i = 0; i < t.size(); i++)
        {
            ent = t.get(i);

            cell = ent.getValue().get(index);

            data = cell.getData();

            data = "<a name=\"" + ent.getKey().replace(".", "_") + "\">" + data + "</a>";

            cell.silentSet(data);
        }
    }

    /**
     * MarkupProcessor is an abstract class that defines common functionality for other processing classes
     * that are defined in and used in the TablePostProcessor.
     * MarkupProcessor objects processMarkups the BBF markup in tables' cells.
     */
    private abstract class MarkupProcessor
    {

        ExclusiveArrayList<String> errList;
        String result;
        boolean proc;

        /**
         * no-argument constructor.
         * instantiates the error buffer,
         * sets the processed flag to false.
         */
        MarkupProcessor()
        {
            errList = new ExclusiveArrayList<String>();
            proc = false;
        }

        /**
         * processMarkups processes the input string, possibly using the Table, Row, and integer passed,
         * stripping the string of BBF markup, and processing aStatement as described in the Template.
         *
         *
         * @param input - a string from the table.
         * @param t - the table that the string is found in.
         * @param r - the row that the string is found in.
         * @param typeCol - the index of the column in the row that will have type information.
         */
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames) throws Exception
        {
            throw new UnsupportedOperationException("this class must implement processMarkups before deMarkup can be called!");
        }

        void deMarkup(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames) throws Exception
        {
            processMarkups(input, t, rowName, r, typeCol, refNames);
            // set flag, saying process has been run.
            proc = true;
        }

        void bypass(String input)
        {
            result = input;
        }

        /**
         * getResult returns the result of processing. An exeption is thrown if the data is not considered processed.
         * @return the result of processing.
         * @throws Exception - if the data has not yet been processed at call time.
         */
        String getResult() throws Exception
        {
            if (!proc)
            {
                throw new Exception("Not able to return because process didn't happen yet.");
            }
            return result;
        }

        /**
         * getErrs returns a string rep of the errors that the processing method reports.
         * @return a String representation of the error output from the processing.
         * @throws Exception - if the data has not yet been processed at call time.
         */
        ExclusiveArrayList<String> getErrs() throws Exception
        {
            if (!proc)
            {
                throw new Exception("Not able to return because process didn't happen yet.");
            }

            return errList;
        }

        /**
         * reset nulls the result, falses the "processed" flag, and resets the error buffer.
         */
        void reset()
        {
            result = null;
            proc = false;
            errList = new ExclusiveArrayList<String>();
        }
    }

    /**
     * BoolProcessor is a MarkupProcessor for BBF markup that is of a boolean nature.
     * Specifically, aStatement replaces "{{true}}" and "{{false}}" with non-markup Strings.
     */
    private class BoolProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            result = input;

            result = result.replace("{{true}}", "<b>true</b>");
            result = result.replace("{{false}}", "<b>false</b>");

            // cushion removed.
//        data = data.replace("{{True}}", "<b>true</b>");
//        data = data.replace("{{False}}", "<b>false</b>");


        }
    }

    /**
     * PaoProcessor is a MarkupProcessor for BBF markup that starts with the "parameter" and/or "object" keywords.
     */
    private class PaoProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            StringBuffer buff;
            String[] parts;
            String temp, shortName, mark, full, searchItem, moddedItem;
            int start, end, index;

            result = input;

            String[] markups =
            {
                "param", "object"
            };

            for (int i = 0; i < markups.length; i++)
            {
                mark = markups[i];

                if (input.contains(mark))
                {
                    buff = new StringBuffer();

                    buff.append(result);

                    end = 0;
                    start = buff.indexOf("{{" + mark);
                    while (start >= 0)
                    {
                        end = buff.indexOf("}}", start) + 2;

                        while (buff.length() > end + 1 && buff.charAt(end) == '}')
                        {
                            end++;
                        }

                        temp = buff.substring(start, end);

                        if (temp.equals("{{" + mark + "}}"))
                        {
                            shortName = rowName;

                            if (shortName.endsWith("."))
                            {
                                shortName = shortName.substring(0, shortName.length() - 2);
                            }

                            shortName = shortName.substring(rowName.lastIndexOf(".") + 1);

                            buff.replace(start, end, "<a href=#" + rowName.replace(".", "_") + ">" + shortName + "</a>");
                            end = start;

                        } else
                        {

                            parts = temp.split("\\|");

                            if (parts[parts.length - 1].endsWith("}}"))
                            {
                                parts[parts.length - 1] = parts[parts.length - 1].substring(0, parts[parts.length - 1].length() - 2);
                            }

                            if (parts.length == 2)
                            {
                                // get the info for parts[1], using closest match or whatever.


                                searchItem = parts[1];

                                index = -1;
                                

                                if (mark.equals("object"))
                                {

                                    moddedItem = searchItem + ".{i}.";
                                    index = t.indexOfClosestMatch(moddedItem, rowName);

                                    if (index == -1)
                                    {
                                        moddedItem = searchItem + ".";
                                        index = t.indexOfClosestMatch(moddedItem, rowName);
                                    }

                                }

                                if (index == -1)
                                {
                                    index = t.indexOfClosestMatch(searchItem, rowName);
                                }


                                if (index == -1)
                                {
                                    errList.add("not able to find " + searchItem + " for the row " + rowName);

                                } else
                                {

                                    full = t.get(index).getKey().replace(".", "_");

                                    buff.replace(start, end, "<a href=#" + full + ">" + parts[1] + "</a>");
                                    end = start;
                                }
                            }
                        }

                        start = buff.indexOf("{{" + mark, end);
                    }

                    result = buff.toString();

                }
            }
        }
    }

    /**
     * SectionProcessor is a MarkupProcessor for BBF markup that starts with the "section" keyword.
     *
     */
    private class SectionProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
//            result = input;
//
//            result = result.replace("{{section}}", "\n-------\n");

            // TODO: implement this 

            bypass(input);
        }
    }

    /**
     * ListProcessor is a MarkupProcessor for BBF markup that denotes lists:
     * either starting with "list" or containing only "nolist".
     */
    private class ListProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {


            StringBuffer buff;
            String[] parts;
            String temp;
            int start, end;

            result = input;

            if (input != null)
            {

                if (input.contains("{{list") && !input.contains("{{nolist"))
                {
                    buff = new StringBuffer();
                    buff.append(input);

                    start = buff.indexOf("{{list");
                    while (start >= 0)
                    {
                        end = buff.indexOf("}}", start) + 2;
                        temp = buff.substring(start, end);

                        parts = temp.split("\\|");

                        parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                        switch (parts.length)
                        {
                            case 1:
                            {
                                buff.replace(start, end, "A list of this type of item.");
                                end = start;
                                break;
                            }

                            case 2:
                            {
                                buff.replace(start, end, "A list of this type of item, " + parts[1] + ".");
                                end = start;
                                break;
                            }

                            default:
                            {
                                errList.add("\n" + rowName + ": Inappropriate number of variables in list");
                                break;
                            }
                        }


                        start = buff.indexOf("{{list", end);
                    }

                    result = buff.toString();
                }

            }

            result.replace("{{nolist}}", "");
        }
    }

    /**
     * EnumProcessor is a MarkupProcessor for BBF markup that denotes enumerations:
     * either starting with "enum" or containing only "noenum".
     */
    private class EnumProcessor extends MarkupProcessor
    {

        @Override
        @SuppressWarnings("empty-statement")
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            ArrayList<BBFEnum> nums;
            ArrayList buck;
            StringBuffer buff, numBuff;
            String[] parts;
            String temp, eName, vName;
            int start, end, loc, numIndex;

            result = input;

            if (input != null)
            {


                if (input.contains("{{enum") && !input.contains("{{noenum"))
                {
                    buff = new StringBuffer();
                    numBuff = new StringBuffer();
                    buff.append(input);
                    nums = new ArrayList<BBFEnum>();

                    buck = r.getBucket();

                    for (int i = 0; i < buck.size(); i++)
                    {
                        if (buck.get(i) instanceof BBFEnum)
                        {
                            nums.add((BBFEnum) buck.get(i));
                        }
                    }

                    if (nums.size() > 0)
                    {
                        numBuff.append("<pre>");
                        for (int j = 0; j < nums.size(); j++)
                        {

                            numBuff.append("\n\t");
                            numBuff.append("<a name=\"");
                            numBuff.append(rowName.replace(".", "_"));
                            numBuff.append("_e:");
                            numBuff.append(nums.get(j).getValue());
                            numBuff.append("\">");
                            numBuff.append(nums.get(j).getValue());
                        }
                        numBuff.append("</pre>");

                        if (!input.contains("{{enum}}"))
                        {
                            buff.append("<br><br>");

                            if ((r.get(typeCol)).getData().contains("list"))
                            {
                                buff.append("Each list item is an ");
                            }

                            buff.append("Enumeration of:");
                            buff.append(numBuff);
                        }
                    }

                    start = buff.indexOf("{{enum");
                    while (start >= 0)
                    {
                        end = buff.indexOf("}}", start) + 2;
                        temp = buff.substring(start, end);

                        parts = temp.split("\\|");

                        parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                        switch (parts.length)
                        {
                            case 1:
                            {
                                buff.replace(start, end, numBuff.toString());

                                end = start;
                                break;
                            }

                            case 2:
                            {

                                buff.replace(start, end, "<a href=#" + rowName.replace(".", "_") + "_e:" + parts[1] + ">" + parts[1] + "</a>");

                                end = start;

                                break;
                            }

                            case 3:
                            {
                                eName = parts[1];
                                vName = parts[2];

                                loc = t.indexOfClosestMatch(vName, rowName);
                                vName = t.get(loc).getKey().replace(".", "_");



                                // fill nums with other var's enums
                                buck = t.get(loc).getValue().getBucket();
                                nums = new ArrayList<BBFEnum>();

                                for (int i = 0; i < buck.size(); i++)
                                {
                                    if (buck.get(i) instanceof BBFEnum)
                                    {
                                        nums.add((BBFEnum) buck.get(i));
                                    }
                                }

                                // check if enum with eName is there.

                                numIndex = -1;
                                for (numIndex = 0; numIndex < nums.size() && nums.get(numIndex).getValue().equals(eName); numIndex++);

                                if (numIndex < 0 || numIndex >= nums.size())
                                {
                                    errList.add("\n" + t.get(loc).getKey() + " DOES NOT list enum: " + eName +
                                            ".\n   It MUST, for description for " + rowName + ".");
                                    buff.replace(start, end, "<i>" + eName + "</i> (from " + t.get(loc).getKey() + ")");
                                } else
                                {
                                    buff.replace(start, end, "<a href=#" + vName + "_e:" + eName + ">" + eName + "</a>");
                                }

                                end = start;

                                break;
                            }

                            default:
                            {
                                errList.add("\n" + rowName + ": Inappropriate number of variables in enum");
                                break;
                            }
                        }


                        start = buff.indexOf("{{enum", end);
                    }

                    result = buff.toString();

                }

            }
            result.replace("{{noenum}}", "");
        }
    }

    /**
     * HiddenProcessor is a MarkupProcessor for BBF markup that denotes hidden values:
     * either starting with "hidden" or containing only "nohidden".
     */
    private class HiddenProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            // TODO: implement this
            bypass(input);
        }
    }

    /**
     * KeyProcessor is a MarkupProcessor for BBF markup that denotes key values:
     * either starting with "key" or containing only "nokeys".
     */
    private class KeyProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            // TODO: implement this
            result = input.replace("{{nokeys}}", "");
        }
    }

    /**
     * MiscProcessor is a MarkupProcessor for BBF markup that denotes empty or null values.
     */
    private class MiscProcessor extends MarkupProcessor
    {

        /**
         * theNulls constructs and returns a HashMap with String keys for types of data, and String values for their null type.
         * @return the map, as described.
         */
        private IndexedHashMap<String, String> theNulls()
        {
            IndexedHashMap<String, String> map = new IndexedHashMap<String, String>();

            map.put("int", "0");
            map.put("long", "0.0");
            map.put("string", "<Empty>");
            map.put("boolean", "false");
            map.put("object", "null");
            map.put("list", "an empty list");
            map.put("datetime", "the Unknown Time value");
            map.put("base64", "null");
            map.put("datatype", "null");

            return map;
        }

        /**
         * getTheNull returns a string representation of the nulltype for the data type passed, null if none known.
         * @param str - the data type
         * @return - a string representation of the nulltype for the data type, or null itself if none is found.
         */
        private String getTheNull(String str)
        {
            IndexedHashMap<String, String> map = theNulls();

            String lower = str.toLowerCase();

            for (int i = 0; i < map.size(); i++)
            {
                if (lower.startsWith(map.get(i).getKey()) || lower.contains(map.get(i).getKey()))
                {
                    return map.get(i).getValue();
                }
            }

            return null;
        }

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            String empty = null, theNull = "null", type = r.get(typeCol).getData();

            if (type != null)
            {

                if (type.contains("string)"))
                {
                    empty = "an empty string";
                } else
                {
                    empty = "<Empty>";
                }

                theNull = getTheNull(type);

                if (theNull == null)
                {
                    errList.add("\nTable Post Processor missing nulltype mapping for type: " + type);
                    theNull = "null";
                }

                empty = "<b>" + empty + "</b>";
                theNull = "<b>" + theNull + "</b>";

                result = input.replace("{{empty}}", empty).replace("{{null}}", theNull);
            }
        }
    }

    /**
     * ReferenceProcessor is a MarkupProcessor for BBF markup that denotes references:
     * either starting with "reference" or contianing only "noreference".
     */
    private class ReferenceProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            StringBuffer buff;
            int start, end;
            String[] parts;
            String temp;

            result = input;

            if (!input.contains("{{noreference}}"))
            {

                buff = new StringBuffer();
                buff.append(result);

                end = 0;
                start = buff.indexOf("{{reference");
                while (start >= 0)
                {
                    end = buff.indexOf("}}", start) + 2;
                    temp = buff.substring(start, end);

                    parts = temp.split("\\|");

                    parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                    switch (parts.length)
                    {
                        case 1:
                        {
                            buff.replace(start, end, rowName);
                            end = start;
                            break;

                        }

                        case 2:
                        {
                            buff.replace(start, end, rowName + " (" + parts[1] + ")");
                            end = start;
                            break;
                        }

                        default:
                        {
                            errList.add("\n" + rowName + ": Inappropriate number of variables in reference");
                            break;
                        }

                    }


                    start = buff.indexOf("{{reference", end);
                }

                result = buff.toString();

            }
            result.replace("{{noreference}}", "");
        }
    }

    /**
     * PatternProcessor is a MarkupProcessor for BBF markup that denotes patterns:
     * either starting with "pattern" or contining only "nopattern".
     */
    private class PatternProcessor extends MarkupProcessor
    {

        // need two passes of the standard switch.
        // first collects all 1-argument patterns, ignores others.
        // second replaces 0-argument patterns with anchored patterns:
        // "Possible patterns: p0, p1," and 1-argument patterns with links to them.
        @Override
        @SuppressWarnings("empty-statement")
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            StringBuffer buff, patBuff;
            int start, end, index;
            String[] parts;
            String temp, searchItem, otherName, tagName;
            ExclusiveArrayList<String> patterns;
            ArrayList buck;
            Row otherRow;

            result = input;

            if (input.contains("{{pattern") && !input.contains("{{nopattern"))
            {

                // get patterns from FirstPass
                buck = r.getBucket();

                index = -1;
                for (index = 0; index < buck.size() && !(buck.get(index) instanceof ExclusiveArrayList && ((ExclusiveArrayList<String>) buck.get(index)).getName().equals(patternListName)); index++);

                patterns = (ExclusiveArrayList<String>) buck.get(index);

                // PASS 2: replacing text

                buff = new StringBuffer();
                buff.append(result);

                end = 0;
                start = buff.indexOf("{{pattern");
                while (start >= 0)
                {
                    end = buff.indexOf("}}", start) + 2;
                    temp = buff.substring(start, end);

                    parts = temp.split("\\|");

                    parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                    switch (parts.length)
                    {
                        case 1:
                        {

                            // list possible patterns.

                            patBuff = new StringBuffer();

                            for (int i = 0; i < patterns.size(); i++)
                            {
                                // collect pattern name, with anchor.
                                patBuff.append("<a name=\"");
                                patBuff.append(rowName);
                                patBuff.append("_p:");
                                patBuff.append(patterns.get(i).trim());
                                patBuff.append("\">");
                                patBuff.append(patterns.get(i).trim());
                                patBuff.append("</a>");

                                if (i < (patterns.size() - 1))
                                {
                                    patBuff.append(",");
                                }
                            }

                            patBuff.append(".");

                            buff.replace(start, end, "\nPossible patterns:<pre>\t" + patBuff.toString() + "</pre>");
                            end = start;
                            break;
                        }

                        case 2:
                        {
                            if (r.getParams().containsKey(hasPatterns))
                            {

                                if (patterns.contains(parts[1]))
                                {
                                    patBuff = new StringBuffer();

                                    // insert link to the pattern.
                                    patBuff.append("<a href=\"#");
                                    patBuff.append(rowName);
                                    patBuff.append("_p:");
                                    patBuff.append(parts[1].trim());
                                    patBuff.append("\">");
                                    patBuff.append(parts[1].trim());
                                    patBuff.append("</a>, ");

                                    buff.replace(start, end, patBuff.toString());

                                } else
                                {
                                    buff.replace(start, end, "<i>" + parts[1] + "</i>");
                                    errList.add("\n" + rowName + " DOES NOT list pattern:" + parts[1] +
                                            "\n   It MUST, for its own description");
                                }

                            }

                            end = start;

                            break;

                        }

                        case 3:
                        {

                            searchItem = parts[2];
                            index = t.indexOfClosestMatch(searchItem, rowName);

                            if (index == -1)
                            {
                                searchItem += ".";
                                index = t.indexOfClosestMatch(searchItem, rowName);
                            }

                            if (index == -1)
                            {
                                searchItem += "{i}.";
                                index = t.indexOfClosestMatch(searchItem, rowName);
                            }

                            if (index == -1)
                            {
                                errList.add("not able to find " + searchItem);
                            } else
                            {
                                otherRow = t.get(index).getValue();
                                otherName = t.get(index).getKey();
                                tagName = otherName.replace(".", "_");

                                if (otherRow.getParams().containsKey(hasPatterns))
                                {

                                    buck = otherRow.getBucket();


                                    for (index = 0; index < buck.size() && !(buck.get(index) instanceof ExclusiveArrayList && ((ExclusiveArrayList<String>) buck.get(index)).getName().equals(patternListName)); index++);

                                    patterns = (ExclusiveArrayList<String>) buck.get(index);

                                    if (patterns.contains(parts[1]))
                                    {
                                        patBuff = new StringBuffer();

                                        // insert link to the pattern.
                                        patBuff.append("<a href=\"#");
                                        patBuff.append(tagName);
                                        patBuff.append("_p:");
                                        patBuff.append(parts[1].trim());
                                        patBuff.append("\">");
                                        patBuff.append(parts[1].trim());
                                        patBuff.append("</a>, ");

                                        buff.replace(start, end, patBuff.toString());
                                    } else
                                    {
                                        errList.add("\n" + otherName + " DOES NOT list pattern: " + parts[1] +
                                                ".\n   It MUST, for description for " + rowName + ".");
                                        buff.replace(start, end, "<i>" + parts[1] + "</i> (from " + otherName + ")");
                                    }


                                }

                            }
                            end = start;
                            break;
                        }

                        default:
                        {

                            errList.add("\n" + rowName + ": Inappropriate number of variables in reference");

                            break;
                        }

                    }


                    start = buff.indexOf("{{pattern", end);
                }

                result = buff.toString();

            }
            result.replace("{{noreference}}", "");
        }
    }

    /**
     * UnitsProcessor is a MarkupProcessor for BBF markup that denotes units.
     */
    private class UnitsProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames)
        {
            // TODO: implement this
            bypass(input);
        }
    }

    /**
     * BibrefProcessor is a MarkupProcessor for BBF markup that denotes bibefs.
     *
     */
    private class BibrefProcessor extends MarkupProcessor
    {

        @Override
        void processMarkups(String input, Table t, String rowName, Row r, int typeCol, HashMap<String, String> refNames) throws Exception
        {
            StringBuffer buff;
            String realName, temp, markupName;
            int start, end;
            String[] parts;

            result = input;


            if (input.contains("{{bibref"))
            {
                if (refNames == null)
                {
                    throw new Exception("there are bibrefs, but no bibliographic data. Table version: " + t.getVersion());
                }

                buff = new StringBuffer();
                buff.append(result);

                end = 0;
                start = buff.indexOf("{{bibref");
                while (start >= 0)
                {
                    end = buff.indexOf("}}", start) + 2;
                    temp = buff.substring(start, end);

                    parts = temp.split("\\|");

                    parts[parts.length - 1] = parts[parts.length - 1].replace("}}", "");

                    switch (parts.length)
                    {
                        case 2:
                        {
                            // has a document argument, like aStatement should. This is the markup name for the referenced documents.
                            markupName = parts[1].trim();
                            // lookup the document's real name.
                            realName = refNames.get(markupName);
                            // make a link of this, with text of the document's real name.

                            buff.replace(start, end, "<a href=\"#" + markupName + "\">" + realName + "</a>");
                            end = start;
                            break;

                        }

                        case 3:
                        {
                            // has a document argument, like aStatement should. This is the markup name for the referenced documents.
                            markupName = parts[1].trim();
                            // lookup the document's real name.
                            realName = refNames.get(markupName);
                            // make a link of this, with text of the document's real name.

                            buff.replace(start, end, "<a href=\"#" + markupName + "\">" + realName + "</a>" + " (" + parts[2] + ")");
                            end = start;
                            break;
                        }

                        default:
                        {
                            errList.add("\n" + rowName + ": Inappropriate number of variables in bibref");
                            break;
                        }
                    }

                    start = buff.indexOf("{{bibref", end);
                }

                result = buff.toString();
            }
        }
    }
}

