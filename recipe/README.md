# What is a recipe
These recipes are the automation that combines infrastructure, software, configuration, and data to create a fully functional system.

There are four types of recipe
1. Independent
An independent recipe does not depend on any other recipes, it will typically perform a single function such as installing and configuring OpenSSHD on a range of distributions or platforms.
2. Complex
A complex recipe has child components, effectively sub-recipes that are used based on the scenario its used in. An example may be a apache2 install that installs different modules depending on what its going to be used for.
3. Composite
A composite uses a combination of other recipes and its own functions to deliver the outcome it needs. An example of a composite receipe could be one to create a LAMP web server, it uses independent recipes to deploy Apache, MySQL, and PHP and then wraps its own code around those changes.
For clarity a composite recipe may do everything that an independent or complex recipe does within its own recipe, but it also uses other recipes to delvier some of its changes. And you can have composites of composites.
4. Alias
An alias recipe is exactly as it sounds, an alternative name for another recipe. An example could be a recipe called php that installs the latest version of php available for that distribution or platform.
