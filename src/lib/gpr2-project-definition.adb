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

with Ada.Containers.Indefinite_Ordered_Maps;

package body GPR2.Project.Definition is

   package Project_Views is
     new Ada.Containers.Indefinite_Ordered_Maps (View.Object, Data);

   protected Shared is

      function Get (View : Project.View.Object) return Data;

      procedure Register (Def : Data; View : out Project.View.Object);

      procedure Set (View : Project.View.Object; Def : Data);

   private
      Views : Project_Views.Map;
      N : View.Id := 0;
   end Shared;

   ---------
   -- Get --
   ---------

   function Get (View : Project.View.Object) return Data is
   begin
      return Shared.Get (View);
   end Get;

   --------------
   -- Register --
   --------------

   function Register (Def : Data) return View.Object is
      Result : View.Object;
   begin
      Shared.Register (Def, Result);
      return Result;
   end Register;

   ---------
   -- Set --
   ---------

   procedure Set (View : Project.View.Object; Def : Data) is
   begin
      Shared.Set (View, Def);
   end Set;

   ------------
   -- Shared --
   ------------

   protected body Shared is

      ---------
      -- Get --
      ---------

      function Get (View : Project.View.Object) return Data is
      begin
         return Views (View);
      end Get;

      --------------
      -- Register --
      --------------

      procedure Register (Def : Data; View : out Project.View.Object) is
         Result : constant Project.View.Object := Project.View.From_Id (N + 1);
      begin
         N := N + 1;
         Views.Insert (Result, Def);
         View := Result;
      end Register;

      ---------
      -- Set --
      ---------

      procedure Set (View : Project.View.Object; Def : Data) is
      begin
         Views (View) := Def;
      end Set;

   end Shared;

end GPR2.Project.Definition;
