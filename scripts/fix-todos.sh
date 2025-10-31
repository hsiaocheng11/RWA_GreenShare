#!/bin/bash
# FILE: scripts/fix-todos.sh
# Script to identify and track remaining TODOs

set -e

echo "🔍 GreenShare TODO Analysis"
echo "=========================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Find all TODOs
echo -e "\n${BLUE}🔍 Scanning for TODOs and placeholders...${NC}"

TODO_COUNT=0
PLACEHOLDER_COUNT=0

# Function to count and display TODOs
count_todos() {
    local pattern="$1"
    local description="$2"
    
    echo -e "\n${YELLOW}$description:${NC}"
    
    local files=$(grep -r "$pattern" . \
        --exclude-dir=node_modules \
        --exclude-dir=.git \
        --exclude-dir=target \
        --exclude-dir=.next \
        --exclude="*.log" \
        --exclude="*.lock" \
        2>/dev/null || true)
    
    if [ -n "$files" ]; then
        echo "$files" | while IFS= read -r line; do
            echo "  $line"
        done
        local count=$(echo "$files" | wc -l)
        echo -e "${RED}Found $count instances${NC}"
        return $count
    else
        echo -e "${GREEN}✅ No instances found${NC}"
        return 0
    fi
}

# Scan for different types of TODOs
count_todos "TODO" "TODO comments"
TODO_COUNT=$?

count_todos "FIXME" "FIXME comments"
FIXME_COUNT=$?

count_todos "<[A-Z_]*>" "Configuration placeholders"
PLACEHOLDER_COUNT=$?

count_todos "placeholder" "General placeholders"
GENERAL_PLACEHOLDER_COUNT=$?

# Calculate total
TOTAL_COUNT=$((TODO_COUNT + FIXME_COUNT + PLACEHOLDER_COUNT + GENERAL_PLACEHOLDER_COUNT))

echo -e "\n${BLUE}📊 Summary${NC}"
echo "--------"
echo "TODOs: $TODO_COUNT"
echo "FIXMEs: $FIXME_COUNT" 
echo "Config placeholders: $PLACEHOLDER_COUNT"
echo "General placeholders: $GENERAL_PLACEHOLDER_COUNT"
echo "Total issues: $TOTAL_COUNT"

if [ $TOTAL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}🎉 No TODOs or placeholders found! Code is production-ready.${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠️  $TOTAL_COUNT items need attention before production deployment.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Review and implement remaining TODOs"
    echo "2. Replace configuration placeholders with actual values"
    echo "3. Test all functionality thoroughly"
    echo "4. Re-run this script to verify completion"
    exit 1
fi