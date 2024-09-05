# Acknowledgments

Firt, a word to say this project couldn't exist without the hard work of Jean Baptiste Chanut.

Thanks to him.

# Download the last version

You can download the last release (already compile for you) as a zip file in the release page of the project : https://github.com/thomas-soutif/warframe-market-tool/releases

# How to compile

If you want to install it on your way, follow these steps

## Install the ps2exe package
```powershell
Install-Module -Name ps2exe -Scope CurrentUser
```
## Compile the script to .exe under a cmd on Windows
```cmd
start build.cmd
```

It will do all the necessary step to compile the script, the configuration path and the .xml file needed.


# Run the program while developing

You can simply execute on a Windows terminal

```cmd
powershell .\run_as_development.ps1
```

It will create a ```build_dev``` directory where you can configure your ```config.json```


# Execute without compiling

You can start the shortcut with absolute path so you can move it


# How to use

## Research bar

It allow you to see stats on specific set, parts of the set and your orders on it.


## Reprice

The reprice button reprice every visible orders you have on your account automaticaly.
Taking curent orders and statistics of the items to give you the best price.

If there is an order that give more or equal that what you ask for, 
it will show you another screen with top orders and ask you what ou want to do.

Exemple: the auto price want you to sell for 11 PL but someone want to buy for 10 PL.


## Set stats

Statistics that take time to run but show you best investments for buying parts and selling sets.


## Others buttons

Set to clipboard predefined messages.