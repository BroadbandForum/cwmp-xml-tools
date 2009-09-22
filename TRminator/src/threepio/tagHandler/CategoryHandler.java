/*
 * File: CategoryHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.tagHandler;

/**
 * CategoryHandler is a General Tag Handler for "category" tags.
 * @author jhoule
 */
public class CategoryHandler extends GeneralTagHandler{

    @Override
    public String getTypeHandled()
    {
        return "category";
    }
}
