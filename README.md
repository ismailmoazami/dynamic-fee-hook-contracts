# Dynamic Fee Hook 
## Hook contract for dynamically adjusting fees based on network gas fees
- We will have a moving average that is average of gas fees 
- This moving average will be updated every tx on pool(swap, modifing liquidity etc.)
- If network fee be more than 10 % above of this moving average, then fees conducted from user will be 50 % of base fee
- If network fee be more than 10% below of this moving average, then fees conducted from user will be 200% of base fee
- Otherwise just contract will conduct base fee from user(normal network fee)
 