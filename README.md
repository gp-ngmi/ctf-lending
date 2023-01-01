# CTF Lending

### Playing the CTF

Install [foundry](https://github.com/foundry-rs/foundry#installation).

```sh
forge install
forge build --force

# make changes to `src/Attacker.sol`
# run the test which will check for the win condition
forge test
```

### Review
I took 2 days for resolving this CTF.
First day :
    I thought the solution was to leverage our position like deposit 10 ctf then borrow 9 then deposit 9 borrow 8 ...
    But at the end we only have 9 ctf token of difference ~=9k usd.
    The fact that the price of a ctf token is hard coded prevented me to make any swap.
    I knew I need to do something with the lp token but I didn't find something interested.

Second day :
    During the second day, I understand the possibility of manipulating the price of an lp token.
    The last problem was to increase our amount of lp "artificially".
    I was able to surpass my last issue and then I was able to conclude this ctf.

