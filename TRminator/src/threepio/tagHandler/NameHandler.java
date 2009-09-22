/*
 * File: NameHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

/**
 * NameHandler is a General Tag Handler for "name" tags.
 * @author jhoule
 */
public class NameHandler extends GeneralTagHandler
{

    @Override
    public String getTypeHandled()
    {
        return "name";
    }
}
