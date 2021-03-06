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

--  This container is designed to contain the set of imports for a specific
--  project. It is used to detect duplicate imported projects in with clauses
--  for example. We also have fast check/access for any imported project name.

with Ada.Iterator_Interfaces;
with GPR2.Containers;

private with Ada.Containers.Indefinite_Ordered_Maps;

package GPR2.Project.Import.Set is

   type Object is tagged private
     with Constant_Indexing => Constant_Reference,
          Default_Iterator  => Iterate,
          Iterator_Element  => Project.Import.Object;

   function Is_Empty (Self : Object) return Boolean;

   procedure Clear (Self : in out Object);

   function Length (Self : Object) return Containers.Count_Type;

   procedure Insert (Self : in out Object; Import : Project.Import.Object);

   procedure Delete (Self : in out Object; Path_Name : GPR2.Path_Name.Object)
     with Pre => Self.Contains (Path_Name);

   function Contains
     (Self : Object; Path_Name : GPR2.Path_Name.Object) return Boolean;

   function Contains (Self : Object; Base_Name : Simple_Name) return Boolean;

   function Element
     (Self : Object; Base_Name : Simple_Name) return Import.Object
     with Pre => Self.Contains (Base_Name);

   function Element
     (Self : Object; Path_Name : GPR2.Path_Name.Object) return Import.Object
     with Pre => Self.Contains (Path_Name);

   type Cursor is private;

   No_Element : constant Cursor;

   function Element (Position : Cursor) return Project.Import.Object
     with Post =>
       (if Has_Element (Position)
        then Element'Result.Is_Defined
        else not Element'Result.Is_Defined);

   function Has_Element (Position : Cursor) return Boolean;

   package Import_Iterator is
     new Ada.Iterator_Interfaces (Cursor, Has_Element);

   type Constant_Reference_Type
     (Import : not null access constant Project.Import.Object) is private
     with Implicit_Dereference => Import;

   function Constant_Reference
     (Self     : aliased Object;
      Position : Cursor) return Constant_Reference_Type;

   function Iterate
     (Self : Object) return Import_Iterator.Forward_Iterator'Class;

private

   package Base_Name_Set is new Ada.Containers.Indefinite_Ordered_Maps
     (Simple_Name, Project.Import.Object);

   type Object is tagged record
      Set : Base_Name_Set.Map;
   end record;

   type Cursor is record
      Current : Base_Name_Set.Cursor;
   end record;

   No_Element : constant Cursor :=
                  Cursor'(Current => Base_Name_Set.No_Element);

   type Constant_Reference_Type
     (Import : not null access constant Project.Import.Object) is null record;

end GPR2.Project.Import.Set;
