# Advanced Usage of Git



## Git Submodules

### Concept
> Git submodules allow you to include another Git repository as a subdirectory within your main (parent) repository. Each submodule is an independent Git project with its own commits, pull requests, and pushes. The parent repository includes multiple submodules as part of its structure.

### Example
Let's walk through an example to understand how to use Git submodules.

1. Create a folder named "gitSubmodules" and initialize it as a Git repository:
   ```shell
   mkdir gitSubmodules
   cd gitSubmodules
   git init
   ```

2. Add a remote origin and push the repository to GitHub:
   ```shell
   git remote add origin git@github.com:YOUR_USERNAME/gitSubmodules.git
   echo "About gitSubmodules" >> README.md
   git add .
   git commit -m "Initialize gitSubmodules"
   git push --set-upstream origin main
   ```

   Here, replace "YOUR_USERNAME" with your actual GitHub username.

3. Now, let's add two submodules to the "gitSubmodules" repository:
   ```shell
   git submodule add git@github.com:YOUR_USERNAME/submodule1.git
   git submodule add git@github.com:YOUR_USERNAME/submodule2.git
   ```

   By executing these commands, the submodules "submodule1" and "submodule2" will be added to the "gitSubmodules" repository. This command will clone the remote repositories of the submodules into the root directory of the "gitSubmodules" repository.

   By default, each submodule will be placed in a directory with the same name as the submodule repository.

4. If you run `git status` at this point, you will see that the repository now contains a new file named ".gitmodules" and two new directories: "submodule1" and "submodule2".

   The ".gitmodules" file stores the mapping between the local directory paths and the remote repository URLs of the submodules.

5. Commit and push the changes to the parent repository:
   ```shell
   git add .
   git commit -m "Add submodule1 and submodule2 submodules"
   git push
   ```

   This will push the submodule information to the remote repository as well.

6. If someone else clones the "gitSubmodules" repository, they will initially have empty directories for the submodules. To populate the submodules with their respective contents, they need to run the following commands:
   ```shell
   git submodule init
   git submodule update
   ```

   After running these commands, the submodules' remote files will be synchronized to the local repository, including the commit information for each submodule.

### Use Cases
Git submodules are useful when you need to include other projects within your main project. Each project can have its own separate repository and version control history, ensuring that modifications to the main and submodules do not affect each other.
