/*
 * File: DateHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.tagHandler;

/**
 * DateHandler is a General Tag Handler for "date" tags.
 * @author jhoule
 */
public class DateHandler extends GeneralTagHandler {

    public DateHandler()
    {
        super("Date", "date");
    }

    @Override
    public String getTypeHandled()
    {
        return "date";
    }

     @Override
    public String getFriendlyName()
    {
        return "Date";
    }

}
