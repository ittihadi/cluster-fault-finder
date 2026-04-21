# Fake Coin Problem

One of the problems solvable using a Decrease and Conquer approach.

## Problem
Given a stack of identical *looking* coins, find the (1) counterfeit by doing
a series of weighings on a scale. The scale can indicate whether both sides
are equal, or if one side is heavier than the other. The counterfeit coin is
known to be lighter than the genuine coins.

> [!NOTE]
> There are variations of this problem, such as where it is not known whether
> the counterfeit is lighter or heavier than the rest of the coins, and the
> solution has to determine whether the cointerfeit is lighter or heavier than
> the rest. For this case, extra considerations should be made when performing
> the solve.

## Solution
It's possible to solve this problem using a brute force approach of manually
weighing each pair of coins individually, but this method scales in linear time
as each pair of coins adds an additional comparison that needs to be done.

A better solution is to use a Decrease and Conquer approach:

See that the largest amount of coins you can differentiate using 1 weighing is
3, because if you weigh 2 of the 3 coins and they're balanced, this means that
the third coin in counterfeit. This can be expanded to a larger number of coins
by splitting up each weighing into three groups of coins

1. Split the initial pile of coins into three equally sized groups, if there's
   1 remaining coin, then place that coin in the third pile, if there's 2
   remaining coins, then split those coins among the first two piles
2. Weigh the first two groups of coins, if one of them is lighter, set aside
   the other pile and repeat step 1 on the lighter pile
3. If the scale is balanced, then set aside both groups and repeat step 1 on
   the third group
4. If left with 2 coins, then just weigh the two coins to see which one is the
   counterfeit

## Visualization
Consider you have 8 coins labeled A - H, you can lay them out like this

```
[A] [B] [C] [D] [E] [F] [G] [H]

   ________        ________
       \______[]______/
              /\
             /__\
```
The first step is to divide the coins into three equally sized groups and
divide the remaining coins appropriately
```
Group 1:
[A] [B] [C]

Group 2:
[D] [E] [F]

Group 3:
[G] [H]
```
The next step is to weigh the first two groups and set aside the third for
later
```
Group 3:
[G] [H]

  [A] [B] [C]    [D] [E] [F]
   ________        ________
       \______[]______/
              /\
             /__\
```
We find that groups 1 and 2 are balanced, which means the counterfeit coin is
in the third group. We set aside the first two groups and because the third
group only has two coins, we can directly weigh the two to find the counterfeit
coin

```
Safe Group:
[A] [B] [C] [D] [E] [F]

     [G]
   ________
       \__            [H]
          ---_[]_  ________
              /\ ---__/
             /__\
```
We find that coin G was the lighter one and is therefore the counterfeit.

## Analysis
The Decrease and Conquer approach divides the search space into 3 each
iteration, and at the end of the iteration, you're guaranteed to have 1/3rd
coins left to compare. This means the Decrease and Conquer method of this
problem has a time complexity of `O(log_3(n))`.

The space complexity of this problem is `O(n)`, as the amount of space grows
at the same rate as the amount of coins to compare

### Proof
We can check the maximum number of weighings it would take to discern the
counterfeit coin for different `n` amounts of coins:


| n  | Max Required Measures | Steps                                          |
| -- | :-------------------- | ---------------------------------------------- |
| 1  | -   | -                                                                |
| 2  | 1   | 1 vs 2                                                           |
| 3  | 1   | 1 vs 2 (3 if balanced)                                           |
| 4  | 2   | 12 vs 34 -> 1 vs 2 or 3 vs 4                                     |
| 5  | 2   | 12 vs 34 (5 if balanced) 2 coin step if not                      |
| 6  | 2   | 12 vs 34 -> 2 coin step                                          |
| 7  | 2   | 123 vs 456 (7 if balanced) 3 coin if not                         |
| 8  | 2   | 123 vs 456 (78 2 coin if balanced) 3 coin if not                 |
| 9  | 2   | 123 vs 456 (789 if balanced) -> 3 coin step                      |
| 10 | 3   | 123 vs 456 (789A if balanced -> 4 coin step) -> 3 coin if not    |
| 11 | 3   | 1234 vs 5678 (9AB if balanced -> 3 coin step) -> 4 coin if not   |
| 12 | 3   | 1234 vs 5678 (9ABC if balanced) -> 4 coin step                   |
| .. | ... | ...                                                              |
| 26 | 3   | 123456789 vs ABCDEFGHI (JK-PQ if balanced -> 8 coin step) -> 9 coin step if not |
| 27 | 3   | 123456789 vs ABCDEFGHI (JK-QR if balanced) -> 9 coin step        |
| 28 | 4   | 123456789 vs ABCDEFGHI (JK-RS if balanced -> 10 coin step) -> 9 coin step if not |
| 29 | 4   | 123456789A vs BCDEFGHIJK (LM-ST if balanced -> 9 coin step) -> 10 coin step if not |

We see that `3`, `9`, and `27` are the maximum amount of coins which can be
solved in `n` steps before another step is required. Meaning the maximum number
of coins for `n` weighings is `3^n` coins, it follows that for `c` coins, the
required number of weighings should be `log_3(c)` weighings. Therefore the time
complexity of this algotithm is `O(log_3(n))`.

