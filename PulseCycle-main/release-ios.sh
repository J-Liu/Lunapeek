#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PulseCycle iOS Release Script ===${NC}\n"

# Check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Not on main branch. Current branch: $CURRENT_BRANCH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ On main branch${NC}"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}Error: There are uncommitted changes:${NC}"
    git status --short
    exit 1
fi
echo -e "${GREEN}✓ No uncommitted changes${NC}"

# Check for untracked files
UNTRACKED=$(git ls-files --others --exclude-standard)
if [ -n "$UNTRACKED" ]; then
    echo -e "${YELLOW}Warning: There are untracked files:${NC}"
    echo "$UNTRACKED"
    echo -e "${YELLOW}These files will NOT be included in the release.${NC}"
fi

# Fetch and check sync with remote
echo -e "\n${GREEN}Fetching from remote...${NC}"
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
    AHEAD=$(git rev-list --count origin/main..HEAD)
    BEHIND=$(git rev-list --count HEAD..origin/main)

    if [ "$AHEAD" -gt 0 ]; then
        echo -e "${YELLOW}Local is $AHEAD commits ahead of origin/main${NC}"
    fi
    if [ "$BEHIND" -gt 0 ]; then
        echo -e "${RED}Error: Local is $BEHIND commits behind origin/main. Pull first.${NC}"
        exit 1
    fi
    if [ "$AHEAD" -gt 0 ]; then
        echo -e "${YELLOW}Need to push $AHEAD commits first.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ In sync with origin/main${NC}"

# Get latest iOS tag
LATEST_TAG=$(git tag -l 'ios/*' --sort=-version:refname | head -1)
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="ios/0.1.0"
fi
echo -e "\n${GREEN}Latest iOS tag: ${LATEST_TAG}${NC}"

# Parse version number
VERSION=${LATEST_TAG#ios/}
MAJOR=$(echo $VERSION | cut -d. -f1)
MINOR=$(echo $VERSION | cut -d. -f2)
PATCH=$(echo $VERSION | cut -d. -f3)

# Increment patch version
NEW_PATCH=$((PATCH + 1))
NEW_TAG="ios/${MAJOR}.${MINOR}.${NEW_PATCH}"
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

echo -e "${GREEN}New tag: ${NEW_TAG}${NC}"

# Get current version from xcodeproj
PROJECT_FILE="PulseCycle.xcodeproj/project.pbxproj"
if [ ! -f "$PROJECT_FILE" ]; then
    echo -e "${RED}Error: project.pbxproj not found${NC}"
    exit 1
fi

CURRENT_MARKETING=$(grep -m1 "MARKETING_VERSION" "$PROJECT_FILE" | sed 's/.*= \(.*\);/\1/')
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT_FILE" | sed 's/.*= \(.*\);/\1/')

echo -e "\n${GREEN}Current xcodeproj:${NC}"
echo "  MARKETING_VERSION: $CURRENT_MARKETING"
echo "  CURRENT_PROJECT_VERSION: $CURRENT_BUILD"

# Calculate new build number
if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    NEW_BUILD=$((CURRENT_BUILD + 1))
else
    NEW_BUILD=1
fi

echo -e "\n${GREEN}New xcodeproj:${NC}"
echo "  MARKETING_VERSION: $NEW_VERSION"
echo "  CURRENT_PROJECT_VERSION: $NEW_BUILD"

# Summary
echo -e "\n${YELLOW}=== Summary ===${NC}"
echo -e "Tag:        ${LATEST_TAG} → ${GREEN}${NEW_TAG}${NC}"
echo -e "Marketing:  ${CURRENT_MARKETING} → ${GREEN}${NEW_VERSION}${NC}"
echo -e "Build:      ${CURRENT_BUILD} → ${GREEN}${NEW_BUILD}${NC}"

# Ask for confirmation
echo -e "\n${YELLOW}Proceed with commit and push? [y/N]${NC}"
read -r CONFIRM

# Only proceed if user explicitly types 'y' or 'Y'
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}Cancelled.${NC}"
    exit 0
fi

echo -e "\n${GREEN}Updating xcodeproj...${NC}"
# Update MARKETING_VERSION and CURRENT_PROJECT_VERSION using sed
sed -i '' "s/MARKETING_VERSION = ${CURRENT_MARKETING};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PROJECT_FILE"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PROJECT_FILE"

echo -e "${GREEN}Committing changes...${NC}"
git add "$PROJECT_FILE"
git commit -m "New iOS version" -s

echo -e "${GREEN}Creating tag ${NEW_TAG}...${NC}"
git tag -a "$NEW_TAG" -m "iOS Release $NEW_TAG"

echo -e "${GREEN}Pushing to origin...${NC}"
git push origin main
git push origin "$NEW_TAG"

echo -e "\n${GREEN}=== iOS Release $NEW_TAG completed! ===${NC}"
