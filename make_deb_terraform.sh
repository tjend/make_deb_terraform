#!/bin/bash
# Check the latest terraform version vs the latest packaged version.
# If not the same, build a new package, and push to apt repo.

# set restrictive umask so gpg and ssh keys get correct permissions
umask 0077

# set the gpg home dir to be ./.gnupg
# explicitly use --homedir with gpg
# explicitly use --gnupghome with reprepro
GNUPGHOME=./gnupg
mkdir -p "${GNUPGHOME}"

echo 'getting latest version number'
RELEASES_PAGE="https://releases.hashicorp.com/terraform/"
LATEST_VERSION=$(curl --silent "${RELEASES_PAGE}" | grep "\/terraform\/[0-9]\+\.[0-9]\+\.[0-9]\+\/" | head --lines 1 | cut --delimiter="/" --fields="3")
if [ $? -ne 0 ]; then
  echo "Failed to get the latest version number!"
  exit 1;
fi
echo

echo 'getting latest package version number'
PACKAGE_VERSION=$(curl --silent "https://tjend.github.io/repo_terraform/LATEST")
if [ $? -ne 0 ]; then
  echo "Failed to get the latest package version number!"
  exit 1;
fi
echo

echo 'checking if package version matches latest version'
if [ "${LATEST_VERSION}" == "${PACKAGE_VERSION}" ]; then
  echo "Package version matches latest version - ${LATEST_VERSION}."
  exit 0;
fi
echo

echo 'downloading latest files'
BASE="https://releases.hashicorp.com/terraform/${LATEST_VERSION}/terraform_${LATEST_VERSION}"
URL_LINUX_AMD64="${BASE}_linux_amd64.zip"
URL_SHA256SUMS="${BASE}_SHA256SUMS"
URL_SIG="${BASE}_SHA256SUMS.sig"
curl --silent "${URL_LINUX_AMD64}" > latest_linux_amd64.zip
curl --silent "${URL_SHA256SUMS}" > SHA256SUMS
curl --silent "${URL_SIG}" > SHA256SUMS.sig
echo

echo 'importing hashicorp gpg key'
KEYID="51852D87348FFC4C"
URL_KEY="https://keybase.io/hashicorp/pgp_keys.asc"
curl --silent "${URL_KEY}" | gpg --homedir "${GNUPGHOME}" --import
if [ $? -ne 0 ]; then
  echo "Failed to import hashicorp gpg key!"
  exit 1;
fi
echo

echo 'verifying downloaded signature'
gpg --homedir "${GNUPGHOME}" --trusted-key "${KEYID}" --verify SHA256SUMS.sig SHA256SUMS
if [ $? -ne 0 ]; then
  echo "Failed to verify downloaded signature!"
  exit 1;
fi
echo

echo 'verifying downloaded linux amd64 file'
SHA256SUM_WANTED=$(grep linux_amd64 SHA256SUMS | cut --delimiter=" " --fields="1")
SHA256SUM=$(sha256sum latest_linux_amd64.zip | cut --delimiter=" " --fields="1")
if [ "${SHA256SUM}" != "${SHA256SUM_WANTED}" ]; then
  echo "sha256sum of downloaded linux amd64 zip file incorrect!"
  echo "wanted=${SHA256SUM_WANTED} got=${SHA256SUM}"
  ls -al
  exit 1;
fi
echo

echo 'building linux amd64 package'
fpm --input-type zip --output-type deb --prefix /usr/local/bin --name terraform --version "${LATEST_VERSION}" --architecture amd64 latest_linux_amd64.zip
if [ $? -ne 0 ]; then
  echo "Failed to build the linux amd64 package!"
  ls -l
  exit 1;
fi
echo

# import apt repo signing key, replacing '_' with newline
echo $REPO_TERRAFORM_GPG_KEY | tr '_' '\n' | gpg --homedir "${GNUPGHOME}" --allow-secret-key-import --import

# configure gpg to use SHA512
echo "digest-algo SHA512" >> "${GNUPGHOME}/gpg.conf"

# write apt repo git ssh key, replacing '_' with newline
echo $REPO_TERRAFORM_SSH_KEY | tr '_' '\n' > .id_rsa

# configure ssh to use our ssh key
export GIT_SSH_COMMAND='ssh -i .id_rsa -o StrictHostKeyChecking=no'

echo 'cloning the deb repo'
git clone git@github.com:tjend/repo_terraform.git
if [ $? -ne 0 ]; then
  echo "Failed to clone the deb repo!"
  exit 1;
fi
echo

echo "adding repo files to repo, even if they already exist"
for FILE in $(ls repo_files/); do
  cp --verbose "repo_files/${FILE}" repo_terraform/
done
echo

echo 'adding new deb package using reprepro'
reprepro --basedir ./repo_terraform --confdir ./reprepro/conf --gnupghome "${GNUPGHOME}" includedeb stable "terraform_${LATEST_VERSION}_amd64.deb"
if [ $? -ne 0 ]; then
  echo "Failed to add the new deb package using reprepro!"
  gpg --homedir "${GNUPGHOME}" --list-secret-keys
  exit 1;
fi
echo

echo 'adding latest version file to repo'
echo "${LATEST_VERSION}" > repo_terraform/LATEST
if [ $? -ne 0 ]; then
  echo "Failed to add latest version file to repo!"
  exit 1;
fi
echo

echo 'pushing the updated deb repo'
export GIT_SSH_COMMAND='ssh -i ../.id_rsa -o StrictHostKeyChecking=no'
cd repo_terraform && git add . && HOME=../gitconfig git commit -m "Add terraform ${LATEST_VERSION}" && git push
if [ $? -ne 0 ]; then
  echo "Failed to push the updated deb repo!"
  exit 1;
fi
echo

# cleanup
rm -rf .gnupg .id_rsa

echo 'Script finished successfully!'
exit 0
