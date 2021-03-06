------------------------------------------------------------------------------
--                                                                          --
--                           GPR2 PROJECT MANAGER                           --
--                                                                          --
--                     Copyright (C) 2019-2020, AdaCore                     --
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

with Ada.Strings.Equal_Case_Insensitive;

package body GPR2.Project.Attribute is

   use Ada.Strings;

   ------------
   -- Create --
   ------------

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Index   : Source_Reference.Value.Object;
      Value   : Source_Reference.Value.Object;
      Default : Boolean) return Object is
   begin
      return A : Object := Create (Name, Value) do
         A.Index   := Index;
         A.Default := Default;
      end return;
   end Create;

   function Create
     (Name   : Source_Reference.Identifier.Object;
      Index  : Source_Reference.Value.Object;
      Value  : Source_Reference.Value.Object) return Object is
   begin
      return A : Object := Create (Name, Value) do
         A.Index := Index;
      end return;
   end Create;

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Index   : Source_Reference.Value.Object;
      Values  : Containers.Source_Value_List;
      Default : Boolean := False) return Object is
   begin
      return A : Object := Create (Name, Values) do
         A.Index   := Index;
         A.Default := Default;
      end return;
   end Create;

   overriding function Create
     (Name  : Source_Reference.Identifier.Object;
      Value : Source_Reference.Value.Object) return Object is
   begin
      return Object'
        (Name_Values.Create (Name, Value)
         with Index                => Source_Reference.Value.Undefined,
              Index_Case_Sensitive => True,
              Default              => False);
   end Create;

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Value   : Source_Reference.Value.Object;
      Default : Boolean) return Object is
   begin
      return Object'
        (Name_Values.Create (Name, Value)
         with Index                => Source_Reference.Value.Undefined,
              Index_Case_Sensitive => True,
              Default              => Default);
   end Create;

   overriding function Create
     (Name   : Source_Reference.Identifier.Object;
      Values : Containers.Source_Value_List) return Object is
   begin
      return Object'
        (Name_Values.Create (Name, Values)
         with Index                => Source_Reference.Value.Undefined,
              Index_Case_Sensitive => True,
              Default              => False);
   end Create;

   function Create
     (Name    : Source_Reference.Identifier.Object;
      Values  : Containers.Source_Value_List;
      Default : Boolean) return Object is
   begin
      return Object'
        (Name_Values.Create (Name, Values)
         with Index                => Source_Reference.Value.Undefined,
              Index_Case_Sensitive => True,
              Default              => Default);
   end Create;

   ---------------
   -- Has_Index --
   ---------------

   function Has_Index (Self : Object) return Boolean is
   begin
      return Self.Index.Is_Defined;
   end Has_Index;

   -----------
   -- Image --
   -----------

   overriding function Image
     (Self     : Object;
      Name_Len : Natural := 0) return String
   is
      use GPR2.Project.Registry.Attribute;
      use all type GPR2.Project.Name_Values.Object;

      Name   : constant String := String (Self.Name.Text);
      Result : Unbounded_String := To_Unbounded_String ("for ");
   begin
      Append (Result, Name);

      if Name_Len > 0 and then Name'Length < Name_Len then
         Append (Result, (Name_Len - Name'Length) * ' ');
      end if;

      if Self.Has_Index then
         Append (Result, " (""" & Self.Index.Text & """)");
      end if;

      Append (Result, " use ");

      case Self.Kind is
         when Single =>
            Append (Result, '"' & Self.Value.Text & '"');

            if Self.Value.Has_At_Num then
               Append (Result, " at" & Integer'Image (Self.Value.At_Num));
            end if;

         when List =>
            Append (Result, Containers.Image (Self.Values));
      end case;

      Append (Result, ';');

      return To_String (Result);
   end Image;

   -----------
   -- Index --
   -----------

   function Index (Self : Object) return Source_Reference.Value.Object is
   begin
      return Self.Index;
   end Index;

   -----------------
   -- Index_Equal --
   -----------------

   function Index_Equal (Self : Object; Value : Value_Type) return Boolean is
   begin
      if Self.Index_Case_Sensitive then
         return Self.Index.Text = String (Value);
      else
         return Equal_Case_Insensitive (Self.Index.Text, String (Value));
      end if;
   end Index_Equal;

   ------------
   -- Rename --
   ------------

   overriding function Rename
     (Self : Object;
      Name : Source_Reference.Identifier.Object) return Object is
   begin
      return (Name_Values.Object (Self).Rename (Name) with
                Default              => True,
                Index                => Self.Index,
                Index_Case_Sensitive => Self.Index_Case_Sensitive);
   end Rename;

   --------------
   -- Set_Case --
   --------------

   procedure Set_Case
     (Self                    : in out Object;
      Index_Is_Case_Sensitive : Boolean;
      Value_Is_Case_Sensitive : Boolean) is
   begin
      Self.Set_Case (Value_Is_Case_Sensitive);
      Self.Index_Case_Sensitive := Index_Is_Case_Sensitive;
   end Set_Case;

end GPR2.Project.Attribute;
