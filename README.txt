#############################################################
This is a placeholder README.
If you are the author, please fill in the __sections__ below.
If you are not the author, please bug the author.
#############################################################

## LinkedEntryCustomFields, a plugin for Movable Type
## Author: Mark Paschal, Six Apart
## Version: 1.0
## Released under __LICENSE__
##
## $Id$
 
## OVERVIEW ##

This plugin provides not only conversion of data created by the RightFields
plugin (http://www.staggernation.com/mtplugins/RightFields/) to the native
custom fields format supported by Movable Type but also provides an
additional RightFields custom field type that the native custom fields did
not support, linked entries

 http://www.staggernation.com/mtplugins/RightFields/#TypeLinked

## PREREQUISITES ##

__detail MT version compatibility and anything else the plugin requires__

## FEATURES ##

__A longer description of the plugin's features for those who are still reading__

## INSTALLATION ##

If you are a Subversion user, you can check out the plugin code from the
repository.  The command below will produce a folder that can be put directly
into your MT "plugins" directory:

  svn co \
  http://code.sixapart.com/svn/mtplugins/trunk/LinkedEntryCustomFields/plugins/LinkedEntryCustomFields

If you would like to download a zip archive of the code, go to:

http://code.sixapart.com/trac/mtplugins/changeset/latest/trunk/LinkedEntryCustomFields/?old_path=/&filename=plugin&format=zip

Unzip the archive.  It will produce a folder called "trunk" with the
following structure:

    trunk/
        LinkedEntryCustomFields/
                                plugins/
                                        LinkedEntryCustomFields/
                                                                lib/
                                                                tmpl/
                                                                config.yaml

Copy/move the LinkedEntryCustomFields folder found inside of the trunk/plugins
folder into your Movable Type "plugins" directory.

Once the LinkedEntryCustomFields folder is installed in your installation's
plugins directory you have finished the installation.  Note however that if
you are running Movable Type under FastCGI, you will have to restart your
webserver in order for the plugin to be recognized.

## CONFIGURATION ##

The plugin contains no special configuration outside of the nomal Custom
Fields configuration.  Please see the following for more information:

http://www.movabletype.org/documentation/professional/custom-fields/overview.html

## USAGE ##

If you are upgrading an installation which used the RightFields plugin, you
can convert that data to the native custom fields format by going to your 
system-level Custom Fields preferences (under the preferences navbar menu
in the System Overview).

Click the link on the right sidebar titled "Convert RightFields to Custom
Fields".  You data will be converted immediately and can be utilized via
the normal mechanisms described in the documentation above.

## KNOWN ISSUES ##

__detail any known issues with current version, if any__

## SUPPORT ##

__specify where people can go for support__

## SOURCE CODE ##

Source

SVN Repo:
    http://code.sixapart.com/svn/mtplugins/trunk/LinkedEntryCustomFields

Trac View:
    http://code.sixapart.com/trac/mtplugins/log/trunk/LinkedEntryCustomFields

Plugins:
    http://plugins.movabletype.org/LinkedEntryCustomFields


## LICENSE ##

__specify the license the plugin is released under__

## AUTHOR ##

__insert arbitrary author info, e.g name, email, URL, company, etc__
