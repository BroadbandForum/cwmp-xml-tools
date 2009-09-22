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

    @Override
    public String getTypeHandled()
    {
        return "title";
    }
}
