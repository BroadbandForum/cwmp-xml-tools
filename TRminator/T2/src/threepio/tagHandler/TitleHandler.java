/*
 * File: TitleHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

/**
 * TitleHandler is a General Tag Handler for "title" tags.
 * @author jhoule
 */
public class TitleHandler extends GeneralTagHandler
{

    public TitleHandler()
    {
        super("Title", "title");
    }
//    @Override
//    public String getTypeHandled()
//    {
//        return "title";
//    }
//
//     @Override
//    public String getFriendlyName()
//    {
//        return "Title";
//    }
}
