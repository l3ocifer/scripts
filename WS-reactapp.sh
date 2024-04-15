#!/bin/bash

# Assuming handle_error function and REPO_PATH are defined in the main script or sourced globally.

# Check if React app already exists
if [ -d "$REPO_PATH/$DOMAINNAME" ]; then
    echo "React app already exists. Skipping creation and moving to build."
else
    # Create a React app with a simple structure
    npx create-react-app $REPO_PATH/$DOMAINNAME --template minimal || handle_error "Failed to create a React app"

    # Setting default background and text color if not specified
    BACKGROUND_COLOR=${BACKGROUND_COLOR:-"#FFFFFF"}  # Default white background
    TEXT_COLOR=${TEXT_COLOR:-"#000000"}              # Default black text

    # Creating basic App.css with the background and text color
    cat <<EOF > $REPO_PATH/$DOMAINNAME/src/App.css
.App {
    color: $TEXT_COLOR;
    background-color: $BACKGROUND_COLOR;
    text-align: center;
    margin: 0 auto;
    max-width: 800px;
    padding: 20px;
}
EOF

    # Modifying App.js to include dynamic content loading
    cat <<EOF > $REPO_PATH/$DOMAINNAME/src/App.js
import React from 'react';
import './App.css';

const content = require('./content.json');

function App() {
    return (
        <div className="App">
            {content.map((item, index) => (
                <p key={index}>{item.title}<br/>{item.content}</p>
            ))}
        </div>
    );
}

export default App;
EOF

fi

# Ensure content file exists or create a JSON content structure
if [ ! -f "$REPO_PATH/$DOMAINNAME/src/content.json" ]; then
    echo "Content file not found. Generating sample content..."
    echo '[{"title": "Welcome to Our Organization", "content": "This is an auto-generated content example."}]' > $REPO_PATH/$DOMAINNAME/src/content.json
fi

# Check for images and move them to the React app's public directory
find $REPO_PATH -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.svg" | while read image; do
    target="$REPO_PATH/$DOMAINNAME/public/$(basename "$image")"
    if [ ! -f "$target" ]; then
        mv "$image" "$target" || handle_error "Failed to move the image: $image"
    else
        echo "Image $(basename $image) has already been moved. Skipping..."
    fi
done

# Build the React app
cd $REPO_PATH/$DOMAINNAME
npm run build || handle_error "Failed to build the React app" 
