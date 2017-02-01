------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--         Copyright (C) 2016-2017, Free Software Foundation, Inc.          --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------
--
--  This is the root package of the GPR2 project support library. There is two
--  child units:
--
--     Parser
--        This child unit and all the children are for the low-level parsing
--        and support. This layer is based on the LangKit parser.
--
--     Project
--        This child unit and all the childrent are the high-level API to
--         work with projects. This is the end-user API.

private with Ada.Strings.Unbounded;

package GPR2 is

   Project_Error : exception;
   --  Raised when an error occurs. This exception is raised with a minimal
   --  message but the actual messages are to be found in the Tree log
   --  messages.

   type Project_Kind is
     (K_Configuration, K_Abstract,
      K_Standard, K_Library, K_Aggregate, K_Aggregate_Library);

   --
   --  Name / Value
   --

   type Optional_Name_Type is new String;

   No_Name : constant Optional_Name_Type;

   subtype Name_Type is Optional_Name_Type
     with Dynamic_Predicate => Name_Type'Length > 0;

   subtype Value_Type is String;

   overriding function "=" (Left, Right : Optional_Name_Type) return Boolean;
   overriding function "<" (Left, Right : Optional_Name_Type) return Boolean;

   No_Value : constant Value_Type;

   function Unquote (Str : Value_Type) return Value_Type with
     Post => Unquote'Result (Unquote'Result'First) not in ''' | '"'
             and then Unquote'Result (Unquote'Result'Last) not in ''' | '"'
             and then (Unquote'Result'Length = Str'Length - 2
                       or else Unquote'Result'Length = Str'Length);

   type Case_Sensitive_Name_Type is new String
     with Dynamic_Predicate => Case_Sensitive_Name_Type'Length > 0;
   --  A non case sensitive name

   --
   --  Path name
   --

   type Path_Name_Type is private;
   --  A project path-name, will always be normalized according to the running
   --  target.

   No_Path_Name : constant Path_Name_Type;

   overriding function "=" (Left, Right : Path_Name_Type) return Boolean;
   --  Returns True if Left and Right are referencing the same project. That
   --  is, based on the normalized names.

   function "<" (Left, Right : Path_Name_Type) return Boolean;
   --  Returns True based on the normalized names

   subtype Full_Path_Name is String
     with Dynamic_Predicate =>
       (for some C of Full_Path_Name => C in '/' | '\');

   function Create (Name : Name_Type) return Path_Name_Type;
   --  Given a filename (possibly a full pathname) return a Path_Name_Type. If
   --  the Name is not found in the current working directly, the project file
   --  is looked for in the ADA_PROJECT_PATH if Is_Project is True.

   function Value (File : Path_Name_Type) return Full_Path_Name;
   --  Returns the full pathname for the given Path_Name_Type

   function Base_Name (File : Path_Name_Type) return Name_Type;
   --  Returns the base name for File

private

   use Ada.Strings.Unbounded;

   type Path_Name_Type is record
      As_Is     : Unbounded_String;
      Value     : Unbounded_String;
      Base_Name : Unbounded_String;
   end record;

   overriding function "=" (Left, Right : Path_Name_Type) return Boolean is
     (Left.Value = Right.Value);

   function "<" (Left, Right : Path_Name_Type) return Boolean
     is (Left.Value < Right.Value);

   function Base_Name (File : Path_Name_Type) return Name_Type
     is (Name_Type (To_String (File.Base_Name)));

   No_Name      : constant Optional_Name_Type := "";
   No_Value     : constant Value_Type := "";
   No_Path_Name : constant Path_Name_Type :=
                    (Null_Unbounded_String,
                     Null_Unbounded_String,
                     Null_Unbounded_String);

   function Create_File (Name : Name_Type) return Path_Name_Type;
   --  Create a Path_Name_Type for a file

end GPR2;