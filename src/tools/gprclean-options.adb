------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                       Copyright (C) 2019, AdaCore                        --
--                                                                          --
-- This is  free  software;  you can redistribute it and/or modify it under --
-- terms of the  GNU  General Public License as published by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for more details.  You should have received  a copy of the  GNU  --
-- General Public License distributed with GNAT; see file  COPYING. If not, --
-- see <http://www.gnu.org/licenses/>.                                      --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Fixed;

with GPR2.Version;
with GPRtools.Util;

with GNAT.Command_Line;

package body GPRclean.Options is

   Dummy : aliased Boolean;
   --  Just to support obsolete options

   ------------------------
   -- Parse_Command_Line --
   ------------------------

   procedure Parse_Command_Line
     (Options : out Object; Project_Tree : in out Project.Tree.Object)
   is
      use GNAT.Command_Line;

      Config : Command_Line_Configuration renames Options.Config;

      procedure Value_Callback (Switch, Value : String);
      --  Accept string swithces

      procedure Set_Project (Path : String);
      --  Set project pathname, raise exception if already done

      -----------------
      -- Set_Project --
      -----------------

      procedure Set_Project (Path : String) is
      begin
         if not Options.Project_Path.Is_Defined then
            Options.Project_Path := Project.Create (Optional_Name_Type (Path));

         else
            raise GPRtools.Usage_Error with
              '"' & Path & """, project already """
              & Options.Project_Path.Value & '"';
         end if;
      end Set_Project;

      --------------------
      -- Value_Callback --
      --------------------

      procedure Value_Callback (Switch, Value : String) is

         function Normalize_Value return String is
           (if Value /= "" and then Value (Value'First) = '='
            then Value (Value'First + 1 .. Value'Last) else Value);
         --  Remove leading '=' symbol from value for options like
         --  --config=file.cgrp

         Idx : Natural := 0;

      begin
         if Switch = "-P" then
            Set_Project (Value);

         elsif Switch = "-X" then
            Idx := Ada.Strings.Fixed.Index (Value, "=");

            if Idx = 0 then
               raise GPRtools.Usage_Error with
                 "Can't split '" & Value & "' to name and value";
            end if;

            Options.Context.Insert
              (Name_Type (Value (Value'First .. Idx - 1)),
               Value (Idx + 1 .. Value'Last));

         elsif Switch = "--config" then
            Options.Config_File :=
              Path_Name.Create_File (Name_Type (Normalize_Value));

         elsif Switch = "--autoconf" then
            --  --autoconf option for gprbuild mean that the file have to be
            --  generated if absent. The gprclean have to remove all gprbuild
            --  generated files.

            Options.Remove_Config := True;

            Options.Config_File :=
              Path_Name.Create_File (Name_Type (Normalize_Value));

         elsif Switch = "--target" then
            Options.Target := To_Unbounded_String (Normalize_Value);

         elsif Switch = "-aP" then
            Project_Tree.Register_Project_Search_Path
              (Path_Name.Create_Directory (Name_Type (Value)));

         elsif Switch = "--subdirs" then
            Options.Subdirs := To_Unbounded_String (Normalize_Value);
         end if;
      end Value_Callback;

   begin
      GPRtools.Options.Setup (GPRtools.Options.Object (Options));

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access, "-P:",
         Help => "Project file");

      Define_Switch
        (Config, Options.No_Project'Access,
         Long_Switch => "--no-project",
         Help        => "Do not use project file");

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access,
         Long_Switch => "--target:",
         Help => "Specify a target for cross platforms");

      Define_Switch
        (Config, Options.All_Projects'Access, "-r",
         Help => "Clean all projects recursively");

      Define_Switch
        (Options.Config, Value_Callback'Unrestricted_Access,
         Long_Switch => "--subdirs:",
         Help        => "Real obj/lib/exec dirs are subdirs",
         Argument    => "<dir>");

      Define_Switch
        (Config, Options.Dry_Run'Access, "-n",
         Help => "Nothing to do: only list files to delete");

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access, "-X:",
         Help => "Specify an external reference for Project Files");

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access,
         Long_Switch => "--config:",
         Help => "Specify the configuration project file name");

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access,
         Long_Switch => "--autoconf:",
         Help => "Specify generated config project file name");

      Define_Switch
        (Config, Options.Remain_Useful'Access, "-c",
         Help => "Only delete compiler generated files");

      Define_Switch
        (Config, Value_Callback'Unrestricted_Access,
         "-aP:",
         Help => "Add directory ARG to project search path");

      Define_Switch
        (Config, Dummy'Access, "-eL",
         Help => "For backwards compatibility, has no effect");

      Define_Switch
        (Config, Options.Unchecked_Shared_Lib_Import'Access,
         Long_Switch => "--unchecked-shared-lib-imports",
         Help => "Shared lib projects may import any project");

      Define_Switch
        (Config, Options.Debug_Mode'Access,
         Switch => "-d",
         Help   => "Debug mode");

      Define_Switch
        (Config, Options.Full_Path_Name_For_Brief'Access,
         Switch => "-F",
         Help   => "Full project path name in brief log messages");

      Define_Switch
        (Config, Options.Remove_Empty_Dirs'Access,
         Switch => "-p",
         Help   => "Remove empty build directories");

      Getopt (Config);

      GPR2.Set_Debug (Options.Debug_Mode);

      if Options.Version then
         GPR2.Version.Display
           ("GPRCLEAN", "2018", Version_String => GPR2.Version.Long_Value);
         return;
      end if;

      --  Now read arguments

      GPRtools.Options.Read_Remaining_Arguments
        (Options.Project_Path, Options.Mains);

      Options.Arg_Mains := not Options.Mains.Is_Empty;

      if not Options.Project_Path.Is_Defined then
         Options.Project_Path := GPRtools.Util.Look_For_Default_Project;

         Options.Implicit_Proj := Options.Project_Path.Is_Defined
           and then Options.Project_Path.Dir_Name
                    /= Ada.Directories.Current_Directory;

      elsif Options.No_Project then
         raise GPRtools.Usage_Error with
           "cannot specify --no-project with a project file";
      end if;

      if not Options.Project_Path.Is_Defined then
         Display_Help (Config);
         raise GPRtools.Usage_Error with
           "Can't determine project file to work with";
      end if;

      Options.Clean_Build_Path
        (if Options.Implicit_Proj
         then Path_Name.Create_Directory
                (Name_Type (Ada.Directories.Current_Directory))
         else Options.Project_Path);
   end Parse_Command_Line;

end GPRclean.Options;