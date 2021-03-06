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

package body GPR2.Source_Info is

   ------------------
   -- Dependencies --
   ------------------

   function Dependencies
     (Self  : Object;
      Index : Unit_Index := 1) return Source_Reference.Identifier.Set.Object is
   begin
      return Self.CU_List (Positive (Index)).Dependencies;
   end Dependencies;

   function Dependencies
     (Self : Object;
      Unit : Name_Type) return Source_Reference.Identifier.Set.Object
   is
      Result : Source_Reference.Identifier.Set.Object;
   begin
      for CU of Self.CU_List loop
         if CU.Name = Unit then
            Result.Union (CU.Dependencies);
         end if;
      end loop;

      return Result;
   end Dependencies;

   --------------
   -- Has_Unit --
   --------------

   function Has_Unit (Self : Object; Unit : Name_Type) return Boolean is
   begin
      --  ??? CU_Map should be changed to be a map for unit name -> unit
      for CU of Self.CU_List loop
         if CU.Name = Unit then
            return True;
         end if;
      end loop;

      return False;
   end Has_Unit;

   -----------------
   -- Has_Unit_At --
   -----------------

   function Has_Unit_At
     (Self : Object; Index : Unit_Index) return Boolean is
   begin
      return Self.CU_List.Length >= Containers.Count_Type (Index);
   end Has_Unit_At;

   ----------------
   -- Is_Generic --
   ----------------

   function Is_Generic
     (Self : Object; Index : Unit_Index := 1) return Boolean is
   begin
      return Self.CU_List (Positive (Index)).Is_Generic;
   end Is_Generic;
   ----------
   -- Kind --
   ----------

   function Kind
     (Self  : Object;
      Index : Unit_Index := 1) return Unit.Kind_Type is
   begin
      if Self.Is_Ada then
         return Self.CU_List (Positive (Index)).Kind;
      else
         return Self.Kind;
      end if;
   end Kind;

   -----------
   -- Reset --
   -----------

   procedure Reset (Self : in out Object) is
   begin
      Self.CU_List.Clear;
      Self.CU_Map.Clear;
      Self.Kind          := Unit.S_Separate;
      Self.Parsed        := None;
      Self.Is_RTS_Source := True;
      Self.Is_Ada        := False;
      Self.Timestamp     := Undefined_Time;
   end Reset;

   ---------
   -- Set --
   ---------

   procedure Set
     (Self : in out Object;
      Kind : Unit.Kind_Type) is
   begin
      Self.Is_Ada := False;
      Self.Kind   := Kind;
   end Set;

   -------------
   -- Set_Ada --
   -------------

   procedure Set_Ada
     (Self          : in out Object;
      Units         : Unit.List.Object;
      Is_RTS_Source : Boolean) is
   begin
      Self.Is_Ada        := True;
      Self.CU_List       := Units;
      Self.Is_RTS_Source := Is_RTS_Source;

      if Self.CU_List.Length > 0 then
         Self.Kind := Self.CU_List (1).Kind;
      end if;

      Self.CU_Map.Clear;

      for CU of Units loop
         Self.CU_Map.Insert (CU.Index, CU);
      end loop;
   end Set_Ada;

   ---------------
   -- Unit_Name --
   ---------------

   function Unit_Name
     (Self : Object; Index : Unit_Index := 1) return Name_Type is
   begin
      return Self.CU_List (Positive (Index)).Name;
   end Unit_Name;

   -----------------------
   -- Units --
   -----------------------

   function Units
     (Self : Object) return Unit.List.Object is
   begin
      return Self.CU_List;
   end Units;

   -----------------
   -- Update_Kind --
   -----------------

   procedure Update_Kind (Self : in out Object; Kind : Unit.Kind_Type) is
   begin
      Self.Kind := Kind;
      Self.CU_List (1).Update_Kind (Kind);
      Self.CU_Map (1).Update_Kind (Kind);
   end Update_Kind;

end GPR2.Source_Info;
