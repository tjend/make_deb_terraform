#!/bin/bash
# check the latest terraform version vs the latest package version
# and if not the same, build a new package

# get latest version number
RELEASES_PAGE="https://releases.hashicorp.com/terraform/"
LATEST_VERSION=$(curl --silent "${RELEASES_PAGE}" | grep "\/terraform\/[0-9]\+\.[0-9]\+\.[0-9]\+\/" | head --lines 1 | cut --delimiter="/" --fields="3")

# TODO: get latest package version number

# TODO: check if package is up to date

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
curl --silent "${URL_KEY}" | gpg --quiet --homedir ./.gnupg --import
if [ $? -ne 0 ]; then
  echo "Failed to import hashicorp gpg key!"
  exit 1;
fi
echo

echo 'verifying downloaded signature'
gpg --homedir ./.gnupg --trusted-key "${KEYID}" --verify SHA256SUMS.sig SHA256SUMS
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
  echo "failed to build the linux amd64 package!"
  ls -l
  exit 1;
fi
echo

# push using this script, instead of using .travis.yml, using travis
# environment variables for the packagecloud details - as per
# https://packagecloud.io/docs
#
# set the following travis environment variables:
# - PACKAGECLOUD_REPO
# - PACKAGECLOUD_TOKEN
# - PACKAGECLOUD_USER
echo 'pushing package to packagecloud'
package_cloud push "${PACKAGECLOUD_USER}/${PACKAGECLOUD_REPO}" "terraform_${LATEST_VERSION}_amd64.deb"
if [ $? -ne 0 ]; then
  echo "failed to push the linux amd64 package to packagecloud!"
  exit 1;
fi
echo

echo 'Script finished successfully!'
exit 0
