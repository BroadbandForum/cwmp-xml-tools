/*
 * File: HTMLPrinter.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.printer;

import threepio.printer.container.StringMultiMap;
import threepio.tabler.Tabler;
import threepio.tabler.container.Row;
import threepio.tabler.container.StringCell;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.XTable;

/**
 * A Printer with HTML output.
 * @author jhoule
 */
public class HTMLPrinter extends FilePrinter
{

    /**
     * Reference for row formatting
     */
    private StringMultiMap refHTMLRow;

    /**
     *  No-argument Constructor
     *  Sets up reference for HTML row formatting.
     */
    public HTMLPrinter()
    {
        setUp();
    }

    /**
     * converts a ModelTable to a String of HTML that defines the table.
     * In reality, just calls the super class's convertTable method.
     * @param table - the ModelTable to convert.
     * @return a String of HTML that includes the processed information from the ModelTable.
     * @throws Exception - when conversion cannot complete due to input errors.
     * @see ModelTable
     * @see FilePrinter#convertTable(threepio.tabler.container.XTable) 
     */
    public String convertTable(ModelTable table) throws Exception
    {
        return super.convertTable(table);
    }

    private void setUp()
    {
        // set up Reference for row modifiers.
        refHTMLRow = new StringMultiMap();
        refHTMLRow.add("object", "background-color:khaki");
        refHTMLRow.add(Tabler.HEADER_ROW_NAME, "background-color:silver; font-family:Arial; font-weight:bold");
        rowTag = "TR";

        colTag = "TD";
        leftBrack = '<';
        rightBrack = '>';
    }

    @Override
    public String convertTable(XTable table, boolean diffMode, boolean looks) throws Exception
    {
        if (table == null)
        {
            throw new Exception("table is null!");
        }
        int i = 0;
        int size = table.size();

        Row row = null;
        StringBuffer buff = new StringBuffer(), insertBuff; //sectionBuff;
        String insert, lineBreak = "<br>", rowName;
        StringCell cell = null;
        int lineLen = 60, left = 0, next, lbLen = lineBreak.length();

        buff.append(leftBrack + tableTag + " border=\"1\" cellpadding=\"5\" cellspacing=\"1\"" + rightBrack + newLine);

        for (i = 0; i < size; i++)
        {
            row = table.get(i).getValue();
            rowName = table.get(i).getKey();

            buff.append(newLine + "\t" + leftBrack + rowTag);
            buff.append(getFormattedModifiers(getRowModifiers(row, rowName, diffMode)));
            buff.append(rightBrack);

            for (int j = 0; j < row.size(); j++)
            {
                cell = row.get(j);

                insert = cell.getData();

                if (insert.contains("Wi-Fi Protected Setup"))
                {
                    System.out.println();
                }

                buff.append(newLine + "\t\t" + leftBrack + colTag);

                buff.append(getFormattedModifiers(getCellModifiers(cell, looks)));

                buff.append(rightBrack);

                if (looks)
                {

                    // TODO: make "looks" ignore non-visible characters ("<a>").

                    if (insert.length() > lineLen)
                    {
                        insertBuff = new StringBuffer();

                        insertBuff.append(insert);

                        left = 0;
                        next = insertBuff.indexOf(".");
                        while (next >= 0)
                        {

                            if (next - left < lineLen)
                            {
                                next = insertBuff.indexOf(".", next + 1);
                            } else
                            {
                                insertBuff.insert(next + 1, lineBreak);
                                left = next + lbLen;
                                next = insertBuff.indexOf(".", left);
                            }
                        }

                        insert = insertBuff.toString();
                    }
                }

                buff.append(insert);

                buff.append(leftBrack + "/" + colTag + rightBrack);
            }
            buff.append(newLine + "\t" + leftBrack + "/" + rowTag + rightBrack);
            buff.append(newLine);
        }
        buff.append(leftBrack + "/" + tableTag + rightBrack);


        return buff.toString();
    }

    /**
     * formats modifiers for (newer) HTML standards.
     * @param mods
     * @return a string that will format in HTML, with modifiers inside.
     */
    private String getFormattedModifiers(String mods)
    {
        StringBuffer buff = new StringBuffer();

        if (!(mods == null || mods.isEmpty()))
        {
            buff.append(" style=\"");
            buff.append(mods);
            buff.append('\"');
        }

        return buff.toString();
    }

    /**
     * gets the modifiers, as a string, listed on one line.
     * @param r - the row
     * @param diff - enables or disables the method's insertion of diff modifers.
     * @return the String.
     */
    private String getRowModifiers(Row r, String rowName, boolean diff)
    {
        String temp = "";
        StringBuffer buff = new StringBuffer();


        if (refHTMLRow.containsKey(rowName))
        {
            temp = refHTMLRow.getValsAsString(rowName);

            buff.append(temp);
        }

        for (int i = 0; i < r.size(); i++)
        {

            if (refHTMLRow.containsKey(r.get(i).getData()))
            {


                temp = refHTMLRow.getValsAsString(r.get(i).getData());

                buff.append(temp);
            }



        }

        if (r.getAllCellsFresh() && diff)
        {
            buff.append(";background-color:green");
        }



        return buff.toString();
    }

    /**
     * gets a formatting string for a cell, based on it's contents and/or flags.
     * @param cell - teh cell.
     * @return the modifiers, if any.
     */
    private String getCellModifiers(StringCell cell, boolean looks)
    {
        StringBuffer buff = new StringBuffer();

        if (cell.getChanged())
        {
            buff.append("color:red");
        }

        buff.append(";font-family:Arial");
        if (looks)
        {
            buff.append(";max-width:400px;");
        }

        return buff.toString();
    }

    /**
     * Does "looks" modifications while ignoring HTML tags.
     * @param str - the original string
     * @param len - the max length.
     * @return a String like the original, with newlines inserted to keep
     * lines from getting beyond the max length.
     */
    private String doLooks(String str, int len)
    {
        // TODO: implement this.
      throw new UnsupportedOperationException("not yet implemented");
    }

}
