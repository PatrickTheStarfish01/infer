(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
module F = Format
open Textual
open TextualTestHelpers

(* Inspired by the following Python program:

   def f(x, y, z, t):
      return (x and y) or (z and t)
*)
let python_inspired_text =
  {|
        define f(x: int, y: int, z: int, t: int) : int {
          #b0:
              n0:int = load &x
              if n0 then jmp b1 else jmp b2

          #b1:
              n2:int = load &y
              if n2 then jmp b4(n2) else jmp b2

          #b2:
              n5:int = load &z
              if n5 then jmp b5 else jmp b4(n5)

          #b5:
              n8:int = load &t
              jmp b4(n8)

          #b4(n9: int):
              ret n9

        }
        |}


let%test_module "remove_internal_calls transformation" =
  ( module struct
    let input_text =
      {|
        declare g1(int) : int

        declare g2(int) : int

        declare g3(int) : int

        declare g4(int) : *int

        declare m(int, int) : int

        define f(x: int, y: int) : int {
          #entry:
              n0:int = load &x
              n1:int = load &y
              n3 = __sil_mult_int(g3(n0), m(g1(n0), g2(n1)))
              n4 = m(n0, g3(n1))
              jmp lab1(g1(n3), g3(n0)), lab2(g2(n3), g3(n0))
          #lab1(n6: int, n7: int):
              n8 = __sil_mult_int(n6, n7)
              jmp lab
          #lab2(n10: int, n11: int):
              ret g3(m(n10, n11))
          #lab:
              throw g4(n8)
        }

        define empty() : void {
          #entry:
              ret null
        }|}


    let%expect_test _ =
      let module_ = parse_module input_text |> TextualTransform.remove_internal_calls in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
        declare g1(int) : int

        declare g2(int) : int

        declare g3(int) : int

        declare g4(int) : *int

        declare m(int, int) : int

        define f(x: int, y: int) : int {
          #entry:
              n0:int = load &x
              n1:int = load &y
              n12 = g3(n0)
              n13 = g1(n0)
              n14 = g2(n1)
              n15 = m(n13, n14)
              n3 = __sil_mult_int(n12, n15)
              n16 = g3(n1)
              n4 = m(n0, n16)
              n17 = g1(n3)
              n18 = g3(n0)
              n19 = g2(n3)
              n20 = g3(n0)
              jmp lab1(n17, n18), lab2(n19, n20)

          #lab1(n6: int, n7: int):
              n8 = __sil_mult_int(n6, n7)
              jmp lab

          #lab2(n10: int, n11: int):
              n21 = m(n10, n11)
              n22 = g3(n21)
              ret n22

          #lab:
              n23 = g4(n8)
              throw n23

        }

        define empty() : void {
          #entry:
              ret null

        } |}]
  end )


let%test_module "remove_if_terminator transformation" =
  ( module struct
    let input_text =
      {|
        define f(b1: int, b2: int, b3: int, b4: int, b5: int) : int {
          #entry:
              n1 : int = load &b1
              n2 : int = load &b2
              n3 : int = load &b3
              n4 : int = load &b4
              n5 : int = load &b5
              if n1 && n2 && n3 then jmp lab1 else jmp lab2
          #lab1:
              ret 1
          #lab2:
              if n2 || n1 && n3 then jmp lab3
              else jmp lab4
          #lab3:
              if n1 && (n2 || (n3 && (n4 || n5))) then jmp lab4 else jmp lab5
          #lab4:
              ret 2
          #lab5:
              ret 3
        }

        define g(b1: int, b2: int, b3: int) : int {
          #entry:
              n1 : int = load &b1
              n2 : int = load &b2
              n3 : int = load &b3
              if (n1 || n2) && n3 then jmp lab1 else jmp if2
          #lab1:
              ret 1
          #if2: // we test the situation where the generated label may already exists
              ret 2
        }

        define h(b1: int, b2: int, b3: int) : int {
          #entry:
              n1 : int = load &b1
              n2 : int = load &b2
              n3 : int = load &b3
              if n1 && n2 && n3 then ret 1
              else if n2 || n1 && n3 then ret 2
              else ret 3
        }|}


    let%expect_test _ =
      let module_ = parse_module input_text |> TextualTransform.remove_if_terminator in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
          define f(b1: int, b2: int, b3: int, b4: int, b5: int) : int {
            #entry:
                n1:int = load &b1
                n2:int = load &b2
                n3:int = load &b3
                n4:int = load &b4
                n5:int = load &b5
                jmp lab1, if0, if1, if2

            #if0:
                prune __sil_lnot(n1)
                jmp lab2

            #if1:
                prune __sil_lnot(n2)
                jmp lab2

            #if2:
                prune __sil_lnot(n3)
                jmp lab2

            #lab1:
                prune n1
                prune n2
                prune n3
                ret 1

            #lab2:
                jmp if5, if6, if3, if4

            #if5:
                prune n2
                jmp lab3

            #if6:
                prune n1
                prune n3
                jmp lab3

            #if3:
                prune __sil_lnot(n2)
                prune __sil_lnot(n1)
                jmp lab4

            #if4:
                prune __sil_lnot(n2)
                prune __sil_lnot(n3)
                jmp lab4

            #lab3:
                jmp if10, if11, if12, if7, if8, if9

            #if10:
                prune n1
                prune n2
                jmp lab4

            #if11:
                prune n1
                prune n3
                prune n4
                jmp lab4

            #if12:
                prune n1
                prune n3
                prune n5
                jmp lab4

            #if7:
                prune __sil_lnot(n1)
                jmp lab5

            #if8:
                prune __sil_lnot(n2)
                prune __sil_lnot(n3)
                jmp lab5

            #if9:
                prune __sil_lnot(n2)
                prune __sil_lnot(n4)
                prune __sil_lnot(n5)
                jmp lab5

            #lab4:
                ret 2

            #lab5:
                ret 3

          }

          define g(b1: int, b2: int, b3: int) : int {
            #entry:
                n1:int = load &b1
                n2:int = load &b2
                n3:int = load &b3
                jmp if3, if4, if0, if1

            #if3:
                prune n1
                prune n3
                jmp lab1

            #if4:
                prune n2
                prune n3
                jmp lab1

            #if0:
                prune __sil_lnot(n1)
                prune __sil_lnot(n2)
                jmp if2

            #if1:
                prune __sil_lnot(n3)
                jmp if2

            #lab1:
                ret 1

            #if2:
                ret 2

          }

          define h(b1: int, b2: int, b3: int) : int {
            #entry:
                n1:int = load &b1
                n2:int = load &b2
                n3:int = load &b3
                jmp if7, if4, if5, if6

            #if7:
                prune n1
                prune n2
                prune n3
                ret 1

            #if4:
                prune __sil_lnot(n1)
                jmp if2, if3, if0, if1

            #if5:
                prune __sil_lnot(n2)
                jmp if2, if3, if0, if1

            #if6:
                prune __sil_lnot(n3)
                jmp if2, if3, if0, if1

            #if2:
                prune n2
                ret 2

            #if3:
                prune n1
                prune n3
                ret 2

            #if0:
                prune __sil_lnot(n2)
                prune __sil_lnot(n1)
                ret 3

            #if1:
                prune __sil_lnot(n2)
                prune __sil_lnot(n3)
                ret 3

          } |}]


    let%expect_test _ =
      let module_ = parse_module python_inspired_text |> TextualTransform.remove_if_terminator in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
          define f(x: int, y: int, z: int, t: int) : int {
            #b0:
                n0:int = load &x
                jmp b1, if0

            #if0:
                prune __sil_lnot(n0)
                jmp b2

            #b1:
                prune n0
                n2:int = load &y
                jmp if2, if1

            #if2:
                prune n2
                jmp b4(n2)

            #if1:
                prune __sil_lnot(n2)
                jmp b2

            #b2:
                n5:int = load &z
                jmp b5, if3

            #if3:
                prune __sil_lnot(n5)
                jmp b4(n5)

            #b5:
                prune n5
                n8:int = load &t
                jmp b4(n8)

            #b4(n9: int):
                ret n9

          } |}]
  end )


let%test_module "let_propagation transformation" =
  ( module struct
    let input_text =
      {|

        define f(x: int, y: int) : int {
          #entry:
              n0:int = load &x
              n1:int = load &y
              n3 = __sil_mult_int(n0, n1)
              n4 = __sil_minusa(n3, n0)
              jmp lab(n4)
          #lab(n5: int):
              n6 = __sil_neg(n1)
              n7 = __sil_plusa(n6, n3)
              n8 = 42 // dead
              ret n7
        } |}


    let%expect_test _ =
      let module_ = parse_module input_text |> TextualTransform.let_propagation in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
        define f(x: int, y: int) : int {
          #entry:
              n0:int = load &x
              n1:int = load &y
              jmp lab(__sil_minusa(__sil_mult_int(n0, n1), n0))

          #lab(n5: int):
              ret __sil_plusa(__sil_neg(n1), __sil_mult_int(n0, n1))

        } |}]
  end )


let%test_module "out-of-ssa transformation" =
  ( module struct
    let input_text =
      {|
          define f(x: int, y: int) : int {
            #entry:
                n0:int = load &x
                n1:int = load &y
                jmp lab1(n0, n1), lab3(n1, __sil_mult_int(n1, n0))

            #lab1(n2: int, n3: int):
                jmp lab2(n3, n2)

            #lab2(n4: int, n5: int):
                ret __sil_plusa(n4, n5)

            #lab3(n6: int, n7: int):
                jmp lab2(n6, n7)

        } |}


    let%expect_test _ =
      let module_ = parse_module input_text |> TextualTransform.out_of_ssa in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
        define f(x: int, y: int) : int {
          #entry:
              n0:int = load &x
              n1:int = load &y
              store &__SSA2 <- n0:int
              store &__SSA3 <- n1:int
              store &__SSA6 <- n1:int
              store &__SSA7 <- __sil_mult_int(n1, n0):int
              jmp lab1, lab3

          #lab1:
              n2:int = load &__SSA2
              n3:int = load &__SSA3
              store &__SSA4 <- n3:int
              store &__SSA5 <- n2:int
              jmp lab2

          #lab2:
              n4:int = load &__SSA4
              n5:int = load &__SSA5
              ret __sil_plusa(n4, n5)

          #lab3:
              n6:int = load &__SSA6
              n7:int = load &__SSA7
              store &__SSA4 <- n6:int
              store &__SSA5 <- n7:int
              jmp lab2

        } |}]


    let%expect_test _ =
      let module_ =
        parse_module python_inspired_text |> TextualTransform.remove_if_terminator
        |> TextualTransform.out_of_ssa
      in
      F.printf "%a" Module.pp module_ ;
      [%expect
        {|
        define f(x: int, y: int, z: int, t: int) : int {
          #b0:
              n0:int = load &x
              jmp b1, if0

          #if0:
              prune __sil_lnot(n0)
              jmp b2

          #b1:
              prune n0
              n2:int = load &y
              jmp if2, if1

          #if2:
              prune n2
              store &__SSA9 <- n2:int
              jmp b4

          #if1:
              prune __sil_lnot(n2)
              jmp b2

          #b2:
              n5:int = load &z
              jmp b5, if3

          #if3:
              prune __sil_lnot(n5)
              store &__SSA9 <- n5:int
              jmp b4

          #b5:
              prune n5
              n8:int = load &t
              store &__SSA9 <- n8:int
              jmp b4

          #b4:
              n9:int = load &__SSA9
              ret n9

        } |}]
  end )
