/*
 * File: OrganizationHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

/**
 * OrganizationHandler is a General Tag Handler for "organization" tags.
 * @author jhoule
 */
public class OrganizationHandler extends GeneralTagHandler
{
  public OrganizationHandler()
  {
      super("Org", "organization");
  }

//    @Override
//    public String getTypeHandled()
//    {
//        return "organization";
//    }
//
//     @Override
//    public String getFriendlyName()
//    {
//        return "Org";
//    }
}
